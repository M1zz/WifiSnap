import AppIntents
import Foundation

/// 위젯에서 읽는 와이파이 목록 (App Group 공유 저장소)
enum WidgetNetworks {
    static func all() -> [SavedNetwork] {
        guard let data = SharedDefaults.store.data(forKey: SharedDefaults.savedNetworksKey),
              let networks = try? JSONDecoder().decode([SavedNetwork].self, from: data)
        else { return [] }
        // 최근에 저장(=연결)한 것부터
        return networks.sorted { $0.savedAt > $1.savedAt }
    }

    static func latest() -> SavedNetwork? { all().first }

    static func network(id: String) -> SavedNetwork? {
        all().first { $0.id.uuidString == id }
    }
}

/// 위젯 편집 화면의 와이파이 선택 항목
struct WifiNetworkEntity: AppEntity, Identifiable {
    let id: String        // SavedNetwork.id.uuidString
    let ssid: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "와이파이" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(ssid)")
    }

    static var defaultQuery = WifiNetworkQuery()

    init(id: String, ssid: String) {
        self.id = id
        self.ssid = ssid
    }

    init(_ network: SavedNetwork) {
        self.init(id: network.id.uuidString, ssid: network.ssid)
    }
}

struct WifiNetworkQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WifiNetworkEntity] {
        identifiers.compactMap { id in
            WidgetNetworks.network(id: id).map(WifiNetworkEntity.init)
        }
    }

    /// 위젯 편집 화면에 나열되는 목록
    func suggestedEntities() async throws -> [WifiNetworkEntity] {
        WidgetNetworks.all().map(WifiNetworkEntity.init)
    }

    /// 위젯을 처음 놓았을 때 기본 선택 — 가장 최근에 연결한 와이파이
    func defaultResult() async -> WifiNetworkEntity? {
        WidgetNetworks.latest().map(WifiNetworkEntity.init)
    }
}

/// 위젯에 고정할 와이파이를 고르는 설정.
/// 고르지 않으면 '가장 최근에 연결한 와이파이'를 따라간다.
struct SelectWifiIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "와이파이 선택"
    static var description = IntentDescription("위젯에 고정할 와이파이를 고릅니다. 고르지 않으면 가장 최근에 연결한 와이파이를 보여줍니다.")

    @Parameter(title: "와이파이")
    var network: WifiNetworkEntity?

    init() {}

    init(network: WifiNetworkEntity?) {
        self.network = network
    }
}
