import Foundation

/// 앱과 위젯이 함께 읽는 저장소.
///
/// 위젯은 앱과 다른 프로세스·다른 컨테이너에서 돌기 때문에, App Group을 거치지 않으면
/// 앱이 저장한 와이파이 목록을 볼 수 없다. 그래서 목록만 이 공유 저장소에 둔다.
/// (안내판·가져온 이름 등 위젯이 쓰지 않는 데이터는 앱 전용 저장소에 그대로 남겨둔다)
enum SharedDefaults {
    /// Signing & Capabilities의 App Groups에 이 그룹이 등록돼 있어야 위젯이 데이터를 본다
    static let appGroupID = "group.com.leeo.wifisnap"
    static let savedNetworksKey = "wifisnap.saved.networks"
    /// 앱이 마지막으로 확인한 '지금 연결된 SSID'.
    /// 위젯은 NEHotspotNetwork.fetchCurrent를 쓸 수 없어(포그라운드 앱 전용) 이 값에 의존한다.
    static let currentSSIDKey = "wifisnap.current.ssid"
    /// QR 위젯이 잠겼는가 (Pro 가 아님). 위젯은 결제를 조회할 수 없어서 앱이 확인한 답을 여기 적어 둔다.
    /// 값이 없으면(앱이 아직 확인 전) 잠그지 않는다 — 산 사람의 위젯이 잠깐이라도 잠기면 안 된다.
    static let widgetLockedKey = "wifisnap.widget.locked"

    /// 잠긴 위젯을 누르면 가는 곳 — 앱의 페이월(위젯 줄을 짚어서).
    static let paywallDeepLink = URL(string: "wifisnap://paywall/widget")!

    static let store: UserDefaults = {
        guard let shared = UserDefaults(suiteName: appGroupID) else {
            // 그룹을 못 만드는 환경 — 앱은 정상 동작하고 위젯만 빈 상태가 된다
            return .standard
        }
        migrateIfNeeded(into: shared)
        return shared
    }()

    /// 공유 저장소를 쓰기 전 버전에서 앱 전용 저장소에 넣어둔 목록을 한 번 옮긴다
    private static func migrateIfNeeded(into shared: UserDefaults) {
        guard shared.data(forKey: savedNetworksKey) == nil,
              let legacy = UserDefaults.standard.data(forKey: savedNetworksKey) else { return }
        shared.set(legacy, forKey: savedNetworksKey)
    }
}
