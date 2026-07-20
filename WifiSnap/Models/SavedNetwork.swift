import Foundation
import CoreLocation

/// 앱에서 스캔했거나 직접 입력한 와이파이 정보
struct SavedNetwork: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var ssid: String
    var password: String
    var savedAt: Date = Date()
    // 연결/공유 당시의 위치 (근처 추천용). 기존 저장분은 nil로 호환됨.
    var latitude: Double?
    var longitude: Double?

    /// 저장된 위치에서 주어진 현재 위치까지의 거리(m). 위치가 없으면 nil.
    func distance(from location: CLLocation) -> CLLocationDistance? {
        guard let latitude, let longitude else { return nil }
        return location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }
}

/// 저장소 (UserDefaults 기반 — 민감한 환경이라면 Keychain으로 교체 권장)
@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var networks: [SavedNetwork] = []

    private let storageKey = "wifisnap.saved.networks"

    init() {
        load()
    }

    /// 네트워크를 저장/갱신. 위치가 주어지면 함께 기록(재연결 시 위치도 최신화).
    func upsert(ssid: String, password: String, latitude: Double? = nil, longitude: Double? = nil) {
        if let idx = networks.firstIndex(where: { $0.ssid == ssid }) {
            networks[idx].password = password
            networks[idx].savedAt = Date()
            if let latitude, let longitude {
                networks[idx].latitude = latitude
                networks[idx].longitude = longitude
            }
        } else {
            networks.insert(
                SavedNetwork(ssid: ssid, password: password, latitude: latitude, longitude: longitude),
                at: 0
            )
        }
        persist()
    }

    func delete(ids: [UUID]) {
        networks.removeAll { ids.contains($0.id) }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedNetwork].self, from: data) else { return }
        networks = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(networks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
