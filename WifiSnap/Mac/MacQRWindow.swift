import SwiftUI

/// 손님에게 돌려 보여 주는 큰 QR 창. 창을 키우면 QR 도 따라 커진다. 아래에서 안내판을 인쇄한다.
struct MacQRWindow: View {
    static let id = "qr"

    let networkID: UUID?

    @EnvironmentObject private var store: NetworkStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var purchases = PurchaseManager.shared
    /// 인쇄할 안내판 테마. 무료는 미드나잇 · 모노, 나머지는 Plus (→ Plan.swift).
    @AppStorage("wifisnap.mac.posterTheme") private var themeID = PosterTheme.all[0].id
    @State private var qrImage: PlatformImage?

    private var network: SavedNetwork? { store.networks.first { $0.id == networkID } }

    private var themes: [PosterTheme] {
        PosterTheme.all.filter { FreeLimit.themeIDs.contains($0.id) || purchases.allows(.allThemes) }
    }

    var body: some View {
        Group {
            if let network {
                content(network)
            } else {
                Text("QR을 만들지 못했어요.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 420, minHeight: 560)
        .navigationTitle(network?.ssid ?? "")
        // 고른 와이파이 없이 열린 창(앱을 켤 때 SwiftUI 가 여는 빈 창 · 되살린 창)은 바로 닫는다 — 메뉴 막대 앱이다
        .onAppear { if networkID == nil { dismiss() } }
        .task(id: network) {
            guard let network else { return }
            qrImage = await Task.detached(priority: .userInitiated) {
                QRCodeGenerator.wifiQRImage(ssid: network.ssid, password: network.password)
            }.value
        }
    }

    private func content(_ network: SavedNetwork) -> some View {
        VStack(spacing: 18) {
            Group {
                if let qrImage {
                    Image(platformImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            // QR 은 어떤 화면 모드에서도 흰 바탕 위 검정이어야 카메라가 잘 읽는다
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(spacing: 6) {
                Text(network.ssid.bidiIsolated)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text((network.password.isEmpty ? String(localized: "없음 (개방)") : network.password).bidiIsolated)
                    .font(.title2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Label("카메라로 QR을 비추면 자동 연결", systemImage: "qrcode.viewfinder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Divider()

            HStack {
                Picker("디자인", selection: $themeID) {
                    ForEach(themes) { Text($0.name).tag($0.id) }
                }
                .fixedSize()
                Spacer()
                Button {
                    printPoster(network)
                } label: {
                    Label("안내판 인쇄", systemImage: "printer")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("p")
                .disabled(qrImage == nil)
            }
        }
        .padding(28)
    }

    /// 아이폰 안내판과 같은 기본 문구로 인쇄한다. A4 는 Plus, 아니면 카드형을 종이에 맞춰 키운다.
    private func printPoster(_ network: SavedNetwork) {
        var design = PosterDesign()
        design.themeID = themes.contains { $0.id == themeID } ? themeID : PosterTheme.all[0].id
        design.layoutID = (purchases.allows(.a4Poster) ? PosterLayout.a4 : .card).rawValue
        MacPosterPrinter.print(
            WifiPosterView(ssid: network.ssid, password: network.password,
                           design: design, qrImage: qrImage),
            title: network.ssid)
    }
}
