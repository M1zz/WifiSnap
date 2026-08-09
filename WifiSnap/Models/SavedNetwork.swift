import Foundation
import CoreLocation
import WidgetKit

/// 앱에서 스캔했거나 직접 입력한 와이파이 정보
struct SavedNetwork: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var ssid: String
    var password: String
    var savedAt: Date = Date()
    // 연결/공유 당시의 위치 (근처 추천용). 기존 저장분은 nil로 호환됨.
    var latitude: Double?
    var longitude: Double?
    /// 내 기기의 핫스팟인지. 기존 저장분은 nil(=아님)로 호환됨.
    ///
    /// 핫스팟은 두 가지가 보통 와이파이와 다르다:
    /// 이 폰이 AP 자신이라 '이 폰 연결'이 성립하지 않고, 나를 따라 움직이니 위치 앵커가 거짓말이 된다.
    /// (Bool?인 것은 호환 때문이다 — 합성된 Decodable은 프로퍼티 기본값을 쓰지 않아서
    ///  非옵셔널로 두면 키가 없는 기존 저장분의 디코딩이 통째로 실패한다)
    var isHotspot: Bool?

    /// 저장된 위치에서 주어진 현재 위치까지의 거리(m). 위치가 없으면 nil.
    func distance(from location: CLLocation) -> CLLocationDistance? {
        guard let latitude, let longitude else { return nil }
        return location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    /// 지도 표시용 좌표. 위치가 기록돼 있지 않으면 nil.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 같은 와이파이인지 비교할 때 쓰는 키.
    ///
    /// SSID 자체는 대소문자를 구분하지만, 사용자가 연결 전에 손으로 적어 만들어 둔 이름('iptime5g')과
    /// 실제로 연결한 뒤 iOS가 알려준 정식 표기('ipTIME5G')가 서로 다른 항목으로 쌓이면
    /// 위치·비밀번호가 엉뚱한 쪽에 붙는다. 화면 표시는 정식 표기로, 동일성 판단은 이 키로 한다.
    /// (이 파일은 위젯 타깃에서도 컴파일되므로 SSIDMatcher 같은 앱 전용 코드에 기대지 않는다)
    static func matchKey(_ ssid: String) -> String {
        ssid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var matchKey: String { Self.matchKey(ssid) }

    /// 이름만 보고 기기 핫스팟으로 짐작한다.
    ///
    /// 핫스팟 SSID는 기기 이름 그대로여서 패턴이 분명하다. 앱이 주변 와이파이 목록을 볼 수 없으니
    /// 이름 말고는 단서가 없고, 틀리면 상세 화면의 토글로 사용자가 바로잡을 수 있다.
    static func looksLikeHotspot(_ ssid: String) -> Bool {
        let lower = ssid.lowercased()
        return ["iphone", "ipad", "galaxy", "pixel", "androidap", "hotspot", "핫스팟"]
            .contains { lower.contains($0) }
    }
}

/// 저장소 (UserDefaults 기반 — 민감한 환경이라면 Keychain으로 교체 권장).
/// 위젯이 같은 목록을 읽어야 하므로 App Group 공유 저장소를 쓴다.
@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var networks: [SavedNetwork] = []

    private let defaults = SharedDefaults.store
    private let storageKey = SharedDefaults.savedNetworksKey

    init() {
        load()
    }

    /// 네트워크를 저장/갱신. 위치가 주어지면 함께 기록(재연결 시 위치도 최신화).
    /// - Parameter verifiedName: ssid가 실제 연결로 iOS가 확인해 준 정식 표기인지.
    ///   true면 미리 만들어 둘 때 적었던 이름을 이 표기로 바로잡는다.
    func upsert(ssid: String, password: String,
                latitude: Double? = nil, longitude: Double? = nil,
                verifiedName: Bool = false) {
        let hotspot = SavedNetwork.looksLikeHotspot(ssid)
        if let idx = index(of: ssid) {
            if verifiedName { networks[idx].ssid = ssid }
            networks[idx].password = password
            networks[idx].savedAt = Date()
            // 이 기능이 생기기 전에 저장된 항목도 다시 저장될 때 한 번은 짐작해 준다.
            // 이미 값이 있으면 사용자가 토글로 정한 것일 수 있으므로 건드리지 않는다.
            if networks[idx].isHotspot == nil { networks[idx].isHotspot = hotspot }
            // 핫스팟에는 위치를 남기지 않는다 — 나를 따라 움직이니 앵커가 곧 거짓이 된다
            if let latitude, let longitude, networks[idx].isHotspot != true {
                networks[idx].latitude = latitude
                networks[idx].longitude = longitude
            }
        } else {
            networks.insert(
                SavedNetwork(ssid: ssid, password: password,
                             latitude: hotspot ? nil : latitude,
                             longitude: hotspot ? nil : longitude,
                             isHotspot: hotspot),
                at: 0
            )
        }
        persist()
    }

    /// 핫스팟 여부를 사용자가 직접 정한다 (이름만으로 한 짐작이 틀렸을 때).
    /// 핫스팟으로 표시하면 의미 없어진 위치 앵커도 함께 지운다.
    func setHotspot(id: UUID, _ isHotspot: Bool) {
        guard let idx = networks.firstIndex(where: { $0.id == id }) else { return }
        networks[idx].isHotspot = isHotspot
        if isHotspot {
            networks[idx].latitude = nil
            networks[idx].longitude = nil
        }
        persist()
    }

    /// 이 와이파이에 위치가 아직 없으면 지금 위치를 앵커로 남긴다.
    ///
    /// 위치는 원래 '앱으로 연결에 성공한 순간'에만 기록됐다. 그러면 설정에서 직접 연결했거나,
    /// 연결 없이 QR만 미리 만들어 둔 와이파이에는 앵커가 영영 생기지 않아 '📍 여기/근처'가 뜨지 않는다.
    /// 지금 그 와이파이에 실제로 붙어 있다는 건 그 자리에 있다는 뜻이므로 앵커로 삼아도 된다.
    ///
    /// 이미 기록된 위치는 덮어쓰지 않는다 — 신호가 겨우 닿는 가장자리에서 갱신되면 앵커가 나빠진다.
    func anchorLocationIfMissing(ssid: String, at location: CLLocation) {
        // 오차가 '근처' 반경보다 큰 위치는 앵커로 쓸 수 없다
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 150,
              let idx = index(of: ssid),
              // 핫스팟은 나를 따라 움직인다 — 지금 위치를 앵커로 박으면 다음 자리에서 곧 거짓이 된다
              networks[idx].isHotspot != true,
              networks[idx].latitude == nil || networks[idx].longitude == nil else { return }
        networks[idx].latitude = location.coordinate.latitude
        networks[idx].longitude = location.coordinate.longitude
        persist()
    }

    /// 이름으로 저장된 네트워크 찾기 (대소문자·앞뒤 공백 차이는 같은 것으로 본다)
    func network(for ssid: String) -> SavedNetwork? {
        index(of: ssid).map { networks[$0] }
    }

    /// 같은 와이파이로 볼 항목의 위치 — 정확히 같은 이름이 우선, 없으면 표기만 다른 것
    private func index(of ssid: String) -> Int? {
        if let exact = networks.firstIndex(where: { $0.ssid == ssid }) { return exact }
        let key = SavedNetwork.matchKey(ssid)
        guard !key.isEmpty else { return nil }
        return networks.firstIndex { $0.matchKey == key }
    }

    func delete(ids: [UUID]) {
        networks.removeAll { ids.contains($0.id) }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedNetwork].self, from: data) else { return }
        networks = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(networks) else { return }
        defaults.set(data, forKey: storageKey)
        // 목록이 바뀌면 위젯의 QR도 다시 그려야 한다
        WidgetCenter.shared.reloadAllTimelines()
    }
}
