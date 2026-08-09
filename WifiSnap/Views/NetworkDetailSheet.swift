import SwiftUI

/// 저장된 네트워크 상세 — 연결용 QR을 크게 보여주고, 연결·안내판 인쇄·QR 공유를 한 곳에서 처리.
/// 목록 행에서는 이름이 잘리지 않는 것이 중요하므로 부가 정보는 모두 이 화면으로 모았다.
struct NetworkDetailSheet: View {
    let network: SavedNetwork
    @ObservedObject var posterStore: PosterDesignStore
    /// '이 폰 연결'을 눌렀을 때 — 시트를 닫고 호출 측에서 연결을 수행한다
    var onConnect: () -> Void
    /// 핫스팟 여부를 사용자가 고쳤을 때 (이름만으로 한 짐작이 틀릴 수 있다)
    var onSetHotspot: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?
    @State private var isGenerating = true
    @State private var showPoster = false
    @State private var revealPassword = false
    @State private var copied = false
    @State private var isHotspot: Bool

    init(network: SavedNetwork,
         posterStore: PosterDesignStore,
         onSetHotspot: @escaping (Bool) -> Void,
         onConnect: @escaping () -> Void) {
        self.network = network
        self.posterStore = posterStore
        self.onSetHotspot = onSetHotspot
        self.onConnect = onConnect
        _isHotspot = State(initialValue: network.isHotspot == true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    qrArea
                    // 이름은 어떤 길이여도 온전히 — 줄바꿈은 허용, 말줄임은 금지
                    Text(network.ssid)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                    passwordRow
                    hotspotRow
                    actionButtons
                }
                .padding(16)
            }
            .navigationTitle("와이파이 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        // 인쇄는 안내판 편집 화면에서 수행 (테마·문구를 고른 뒤 AirPrint)
        .sheet(isPresented: $showPoster) {
            PosterListSheet(store: posterStore, ssid: network.ssid, password: network.password)
        }
        .task {
            let ssid = network.ssid
            let password = network.password
            // 무거운 QR 렌더링은 백그라운드에서 — 시트 애니메이션이 끊기지 않게
            qrImage = await Task.detached(priority: .userInitiated) {
                QRCodeGenerator.wifiQRImage(ssid: ssid, password: password)
            }.value
            isGenerating = false
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var qrArea: some View {
        if isGenerating {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("QR 만드는 중…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else if let qrImage {
            VStack(spacing: 10) {
                Image(uiImage: qrImage)
                    .interpolation(.none)   // QR은 픽셀이 뭉개지면 안 됨
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

                Text("카메라로 비추면 바로 연결돼요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView("QR 생성 실패",
                                   systemImage: "qrcode",
                                   description: Text("네트워크 정보를 확인해 주세요."))
        }
    }

    @ViewBuilder
    private var passwordRow: some View {
        if !network.password.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(revealPassword ? network.password : String(repeating: "•", count: min(network.password.count, 12)))
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)

                Button {
                    revealPassword.toggle()
                } label: {
                    Image(systemName: revealPassword ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    UIPasteboard.general.string = network.password
                    withAnimation { copied = true }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? .green : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 핫스팟 표시 + 그때만 필요한 안내.
    ///
    /// QR이 멀쩡해도 핫스팟이 꺼져 있으면 상대 폰에는 그냥 '네트워크를 찾을 수 없음'이 뜬다.
    /// 원인이 QR이 아니라는 걸 알려 줄 곳이 QR 바로 옆 말고는 없다.
    private var hotspotRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isHotspot) {
                Label("내 핫스팟", systemImage: "personalhotspot")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.orange)
            .onChange(of: isHotspot) { _, value in onSetHotspot(value) }

            if isHotspot {
                Text("보여주기 전에 설정 > 개인용 핫스팟에서 ‘다른 사람의 연결 허용’을 켜 주세요. 꺼져 있으면 QR을 찍어도 네트워크를 찾지 못해요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // 내 핫스팟에는 이 폰이 붙을 수 없다 — 누르면 반드시 실패하는 버튼은 아예 두지 않는다
            if !isHotspot {
                Button {
                    dismiss()
                    onConnect()
                } label: {
                    Label("이 폰 연결", systemImage: "wifi")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Button {
                showPoster = true
            } label: {
                Label("손님용 안내판 인쇄·공유", systemImage: "printer.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
            .tint(.indigo)

            if let qrImage {
                ShareLink(
                    item: Image(uiImage: qrImage),
                    preview: SharePreview("\(network.ssid) 와이파이 QR", image: Image(uiImage: qrImage))
                ) {
                    Label("QR 이미지 공유", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
