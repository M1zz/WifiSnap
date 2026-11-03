import SwiftUI
import VisionKit

/// 카메라를 안내판에 대기만 하면 아이디·비밀번호를 읽는 화면.
///
/// 찍고 → 사진을 확인하고 → 쓰기를 누르는 세 단계를 없앤다. 와이파이 QR이 보이면 그 자리에서,
/// 글자로 아이디와 비밀번호를 둘 다 찾았으면 값이 잠깐 그대로 머무를 때 끝난다.
/// 다 못 찾아도 [이대로 쓰기]로 지금 읽은 줄을 넘기면 퍼즐 화면에서 고칠 수 있다.
struct LiveScanView: View {

    enum Result {
        case qr(WifiCredentials)
        case lines([String])
    }

    /// 이 기기에서 실시간 읽기를 쓸 수 있는지 (안 되면 예전처럼 사진을 찍는다)
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// 읽은 결과와, 끝낸 순간의 사진 (사진 위를 문질러 값을 다시 고를 때 쓴다)
    let onFinish: (Result, UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scanner = ScannerHandle()

    @State private var lines: [String] = []
    @State private var found = WifiCredentials()
    @State private var settle: Task<Void, Never>?
    @State private var finished = false

    var body: some View {
        NavigationStack {
            DataScannerView(handle: scanner, onItems: handle)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) { panel }
                .navigationTitle("와이파이 안내문 촬영")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기", systemImage: "xmark") { dismiss() }
                    }
                }
        }
        .onDisappear { settle?.cancel() }
    }

    /// 지금까지 읽은 아이디·비밀번호와 [이대로 쓰기]
    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(icon: "wifi", label: String(localized: "아이디"), value: found.ssid)
            row(icon: "key.fill", label: String(localized: "비밀번호"), value: found.password)
            Button {
                finish(.lines(lines))
            } label: {
                Text("이대로 쓰기").frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(lines.isEmpty)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func row(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(value.isEmpty ? Color.secondary : .orange)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "…" : value)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 읽은 것 처리

    private func handle(_ items: [RecognizedItem]) {
        guard !finished else { return }

        // QR에는 추측 없는 정답이 들어 있다 — 보이는 즉시 끝낸다
        for case .barcode(let code) in items {
            if let payload = code.payloadStringValue, let qr = WifiQRPayload.parse(payload) {
                return finish(.qr(qr))
            }
        }

        // 화면 위에서 아래로, 같은 줄이면 왼쪽부터 — 사진을 읽을 때와 같은 순서로 파서에 넘긴다
        let texts: [(text: String, row: Int, x: CGFloat)] = items.compactMap { item in
            guard case .text(let text) = item else { return nil }
            let bounds = text.bounds
            let midY = (bounds.topLeft.y + bounds.bottomLeft.y) / 2
            return (text.transcript, Int(midY / 24), bounds.topLeft.x)
        }
        lines = texts
            .sorted { $0.row != $1.row ? $0.row < $1.row : $0.x < $1.x }
            .flatMap { $0.text.components(separatedBy: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let credentials = WifiCredentialParser.parse(lines: lines).credentials
        guard credentials != found else { return }
        found = credentials

        // 둘 다 찾았으면, 값이 잠깐 그대로 머무를 때 끝낸다 (손떨림에 반쯤 읽힌 값으로 끝나지 않게)
        settle?.cancel()
        guard !credentials.ssid.isEmpty, !credentials.password.isEmpty else { return }
        let snapshot = lines
        settle = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            finish(.lines(snapshot))
        }
    }

    private func finish(_ result: Result) {
        guard !finished else { return }
        finished = true
        settle?.cancel()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            let photo = try? await scanner.controller?.capturePhoto()
            onFinish(result, photo)
            dismiss()
        }
    }
}

/// 끝낼 때 사진을 한 장 남기려고 읽기 화면을 붙잡아 둔다
@MainActor
private final class ScannerHandle {
    weak var controller: DataScannerViewController?
}

/// VisionKit 실시간 읽기 화면을 SwiftUI에 얹는다.
private struct DataScannerView: UIViewControllerRepresentable {
    let handle: ScannerHandle
    let onItems: ([RecognizedItem]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .text(languages: ["ko-KR", "en-US"]),
                .barcode(symbologies: [.qr])
            ],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        handle.controller = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onItems = onItems
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onItems: onItems) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onItems: ([RecognizedItem]) -> Void

        init(onItems: @escaping ([RecognizedItem]) -> Void) {
            self.onItems = onItems
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            onItems(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) {
            onItems(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didRemove removed: [RecognizedItem], allItems: [RecognizedItem]) {
            onItems(allItems)
        }
    }
}
