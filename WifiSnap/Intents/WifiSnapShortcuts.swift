import AppIntents
import CoreSpotlight

/// 와이파이 QR 보여주기 — 친구에게 비밀번호 대신 화면을 내미는, 이 앱의 가장 잦은 동작.
struct ShowWifiQRIntent: AppIntent {
    static var title: LocalizedStringResource = "와이파이 QR 보여주기"
    static var description = IntentDescription("지금 연결된 와이파이의 QR을 엽니다. 연결된 와이파이가 저장돼 있지 않으면 가장 최근에 저장한 와이파이를 엽니다.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .showWifiQR
        return .result()
    }
}

/// 와이파이 안내문 촬영 — 카페·숙소에서 안내문을 찍어 바로 연결.
struct ScanWifiPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "와이파이 안내문 촬영"
    static var description = IntentDescription("카메라를 열어 와이파이 안내문을 찍으면 이름과 비밀번호를 읽어 줍니다.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .scanWifiPhoto
        return .result()
    }
}

/// 설치만 하면 단축어 앱 · Spotlight · Siri 에 나타나는 앱 단축어.
struct WifiSnapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowWifiQRIntent(),
            phrases: [
                "\(.applicationName) 와이파이 QR 보여줘",
                "\(.applicationName)에서 와이파이 QR 열어줘",
                "\(.applicationName) QR"
            ],
            shortTitle: "와이파이 QR",
            systemImageName: "qrcode"
        )
        AppShortcut(
            intent: ScanWifiPhotoIntent(),
            phrases: [
                "\(.applicationName)로 와이파이 안내문 찍어줘",
                "\(.applicationName) 와이파이 촬영"
            ],
            shortTitle: "안내문 촬영",
            systemImageName: "camera.viewfinder"
        )
    }
}

// MARK: - 저장한 와이파이 (Spotlight · Siri 가 이름으로 찾는다)

/// 저장한 와이파이 하나. Spotlight 에는 이름만 싣는다 — 비밀번호는 색인하지 않는다.
struct SavedWifiEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "와이파이" }
    static var defaultQuery = SavedWifiQuery()

    let id: String        // SavedNetwork.id.uuidString
    let ssid: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(ssid)")
    }

    init(_ network: SavedNetwork) {
        id = network.id.uuidString
        ssid = network.ssid
    }

    /// 앱이 저장한 목록 — 최근에 저장한 것부터 (App Group 공유 저장소)
    static func all() -> [SavedWifiEntity] {
        guard let data = SharedDefaults.store.data(forKey: SharedDefaults.savedNetworksKey),
              let networks = try? JSONDecoder().decode([SavedNetwork].self, from: data)
        else { return [] }
        return networks.sorted { $0.savedAt > $1.savedAt }.map(SavedWifiEntity.init)
    }

    /// Spotlight 에 싣는 와이파이를 지금 목록에 맞춘다. 앱을 열 때와 뒤로 보낼 때 부른다.
    static func reindex() async {
        guard #available(iOS 18.0, *) else { return }
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: SavedWifiEntity.self)
        try? await index.indexAppEntities(all())
    }
}

@available(iOS 18.0, *)
extension SavedWifiEntity: IndexedEntity {}

struct SavedWifiQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SavedWifiEntity] {
        let wanted = Set(identifiers)
        return SavedWifiEntity.all().filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [SavedWifiEntity] {
        SavedWifiEntity.all().filter { $0.ssid.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [SavedWifiEntity] {
        SavedWifiEntity.all()
    }
}

/// 저장한 와이파이의 QR 을 연다. Spotlight · Siri 결과를 누르면 여기로 온다.
struct OpenSavedWifiIntent: OpenIntent {
    static var title: LocalizedStringResource = "와이파이 QR 열기"
    static var description = IntentDescription("저장한 와이파이 하나를 골라 그 QR 화면을 엽니다.")

    @Parameter(title: "와이파이", description: "QR을 열 저장한 와이파이")
    var target: SavedWifiEntity

    init() {}

    init(target: SavedWifiEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .showNetwork(target.id)
        return .result()
    }
}
