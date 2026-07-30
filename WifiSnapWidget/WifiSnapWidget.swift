import WidgetKit
import SwiftUI

/// 홈 화면에서 바로 보여줄 와이파이 QR 위젯.
///
/// 친구에게 앱을 열지 않고 화면만 보여주면 연결되게 하는 것이 목적이다.
/// 잠금화면 계열(accessory*)은 지원하지 않는다 — 잠긴 폰에서도 보이면
/// 폰을 집어든 누구나 와이파이에 붙을 수 있기 때문.
struct WifiQREntry: TimelineEntry {
    let date: Date
    let ssid: String
    let qrImage: UIImage?

    var hasNetwork: Bool { !ssid.isEmpty }
}

struct WifiQRProvider: TimelineProvider {

    func placeholder(in context: Context) -> WifiQREntry {
        WifiQREntry(date: Date(), ssid: "WifiSnap", qrImage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WifiQREntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WifiQREntry>) -> Void) {
        // 시간이 지나서 바뀔 내용이 없다 — 목록이 바뀌면 앱이 reloadAllTimelines로 깨운다
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }

    private func makeEntry() -> WifiQREntry {
        guard let network = latestNetwork() else {
            return WifiQREntry(date: Date(), ssid: "", qrImage: nil)
        }
        // 위젯 메모리 한도가 빡빡하므로 앱보다 낮은 배율로 만든다 (작은 위젯에서도 충분히 선명)
        let image = QRCodeGenerator.wifiQRImage(ssid: network.ssid,
                                                password: network.password,
                                                scale: 8)
        return WifiQREntry(date: Date(), ssid: network.ssid, qrImage: image)
    }

    /// 가장 최근에 저장(=연결)한 와이파이
    private func latestNetwork() -> SavedNetwork? {
        guard let data = SharedDefaults.store.data(forKey: SharedDefaults.savedNetworksKey),
              let networks = try? JSONDecoder().decode([SavedNetwork].self, from: data)
        else { return nil }
        return networks.max { $0.savedAt < $1.savedAt }
    }
}

struct WifiQRWidgetView: View {
    var entry: WifiQREntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.hasNetwork {
            emptyState
        } else if family == .systemMedium {
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
            VStack(spacing: 6) {
                qr
                Text(entry.ssid)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// QR은 흰 배경 위 검정으로 고정 — 위젯 배경이 어두워도 스캔되도록
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
        StaticConfiguration(kind: "WifiSnapQRWidget", provider: WifiQRProvider()) { entry in
            WifiQRWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("와이파이 QR")
        .description("가장 최근에 연결한 와이파이의 QR을 보여줍니다. 상대가 카메라로 비추면 바로 연결돼요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct WifiSnapWidgetBundle: WidgetBundle {
    var body: some Widget {
        WifiQRWidget()
    }
}
