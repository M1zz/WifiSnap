import WidgetKit
import SwiftUI
import AppIntents

/// 와이파이 QR 위젯 (홈 화면 + 잠금화면).
///
/// 친구에게 앱을 열지 않고 화면만 보여주면 연결되게 하는 것이 목적이다.
///
/// ⚠️ 잠금화면(accessory*) 제약:
///  - 잠금화면 위젯은 시스템이 vibrant 렌더링으로 강제 변환한다(밝기만 남기고 배경이 비쳐 보임).
///    QR은 흑백 대비로 읽히는 것이라 이 변환을 거치면 스캔이 안 될 수 있다.
///  - 크기도 작아(accessoryRectangular ≈ 160×72pt) 모듈이 잘게 뭉갠다.
///  그래서 잠금화면에서는 **탭하면 앱의 QR 화면이 열리는 지름길**을 함께 제공한다.
///  - 잠긴 폰에서도 보이므로, 폰을 집어든 누구나 와이파이 이름을 볼 수 있다는 점은 감수하는 설계다.
struct WifiQREntry: TimelineEntry {
    let date: Date
    let ssid: String
    /// 탭했을 때 앱에서 열 네트워크 id (없으면 앱이 최근 것을 연다)
    let networkID: String?
    let qrImage: UIImage?

    var hasNetwork: Bool { !ssid.isEmpty }

    /// 위젯을 탭하면 앱의 QR 상세로 간다
    var deepLink: URL? {
        guard let networkID else { return URL(string: "wifisnap://qr") }
        return URL(string: "wifisnap://qr?id=\(networkID)")
    }
}

struct WifiQRProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> WifiQREntry {
        WifiQREntry(date: Date(), ssid: "WifiSnap", networkID: nil, qrImage: nil)
    }

    func snapshot(for configuration: SelectWifiIntent, in context: Context) async -> WifiQREntry {
        makeEntry(for: configuration)
    }

    func timeline(for configuration: SelectWifiIntent, in context: Context) async -> Timeline<WifiQREntry> {
        // 시간이 지나서 바뀔 내용이 없다 — 목록이 바뀌면 앱이 reloadAllTimelines로 깨운다
        Timeline(entries: [makeEntry(for: configuration)], policy: .never)
    }

    private func makeEntry(for configuration: SelectWifiIntent) -> WifiQREntry {
        // 고정한 와이파이가 있으면 그것, 없으면 가장 최근에 연결한 것
        let network = configuration.network.flatMap { WidgetNetworks.network(id: $0.id) }
            ?? WidgetNetworks.latest()

        guard let network else {
            return WifiQREntry(date: Date(), ssid: "", networkID: nil, qrImage: nil)
        }
        // 위젯 메모리 한도가 빡빡하므로 앱보다 낮은 배율로 만든다 (작은 위젯에서도 충분히 선명)
        let image = QRCodeGenerator.wifiQRImage(ssid: network.ssid,
                                                password: network.password,
                                                scale: 8)
        return WifiQREntry(date: Date(), ssid: network.ssid,
                           networkID: network.id.uuidString, qrImage: image)
    }
}

struct WifiQRWidgetView: View {
    var entry: WifiQREntry
    @Environment(\.widgetFamily) private var family

    /// 잠금화면 계열인지 — 배경·대비 처리를 달리해야 한다
    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    var body: some View {
        content
            // 탭하면 앱이 열려 이 위젯에 고정된 와이파이의 큰 QR을 보여준다.
            // 잠금화면에서는 vibrant 변환 탓에 위젯의 QR이 스캔되지 않을 수 있어 이 경로가 중요하다.
            .widgetURL(entry.deepLink)
            .containerBackground(for: .widget) {
                if !isAccessory { Color(.systemBackground) }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            // 인라인은 한 줄 텍스트만 — 시각 요소를 넣을 수 없다
            Label(entry.hasNetwork ? entry.ssid : "저장된 와이파이 없음", systemImage: "wifi")

        case .accessoryCircular:
            // 원형은 QR을 넣어도 읽을 수 없는 크기다 — 앱으로 가는 지름길로 쓴다
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.hasNetwork ? "qrcode" : "wifi.slash")
                        .font(.title3)
                    Text("WiFi")
                        .font(.system(size: 9, weight: .semibold))
                }
            }

        case .accessoryRectangular:
            if entry.hasNetwork {
                HStack(spacing: 8) {
                    accessoryQR
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.ssid)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("탭하면 큰 QR")
                            .font(.caption2)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Label("저장된 와이파이 없음", systemImage: "wifi.slash")
                    .font(.caption)
            }

        case .systemMedium:
            if entry.hasNetwork {
                HStack(spacing: 14) {
                    qr
                    VStack(alignment: .leading, spacing: 4) {
                        Label("와이파이", systemImage: "wifi")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(entry.ssid)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("카메라로 비추면 바로 연결")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                emptyState
            }

        default:
            if entry.hasNetwork {
                VStack(spacing: 6) {
                    qr
                    Text(entry.ssid)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                emptyState
            }
        }
    }

    /// 홈 화면용 QR — 흰 배경 위 검정으로 고정해 어떤 위젯 배경에서도 스캔되게 한다
    @ViewBuilder
    private var qr: some View {
        if let image = entry.qrImage {
            Image(uiImage: image)
                .interpolation(.none)   // QR은 픽셀이 뭉개지면 안 됨
                .resizable()
                .scaledToFit()
                .padding(6)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "qrcode")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
        }
    }

    /// 잠금화면용 QR — vibrant 렌더링에서 흰 카드는 통째로 밝아져 대비가 사라지므로 배경 없이 얹는다
    @ViewBuilder
    private var accessoryQR: some View {
        if let image = entry.qrImage {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .font(.title2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("저장된 와이파이 없음")
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("앱에서 한 번 연결하면 여기에 QR이 떠요")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(4)
    }
}

struct WifiQRWidget: Widget {
    var body: some WidgetConfiguration {
        // 위젯을 길게 눌러 '위젯 편집'에서 고정할 와이파이를 고를 수 있다
        AppIntentConfiguration(kind: "WifiSnapQRWidget",
                               intent: SelectWifiIntent.self,
                               provider: WifiQRProvider()) { entry in
            WifiQRWidgetView(entry: entry)
        }
        .configurationDisplayName("와이파이 QR")
        .description("고정한 와이파이의 QR을 보여줍니다. 길게 눌러 '위젯 편집'에서 바꿀 수 있어요.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline
        ])
    }
}

@main
struct WifiSnapWidgetBundle: WidgetBundle {
    var body: some Widget {
        WifiQRWidget()
    }
}
