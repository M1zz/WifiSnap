import Foundation

/// 앱에서 스캔했거나 직접 입력한 와이파이 정보
struct SavedNetwork: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var ssid: String
    var password: String
    var savedAt: Date = Date()
}

/// 저장소 (UserDefaults 기반 — 민감한 환경이라면 Keychain으로 교체 권장)
@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var networks: [SavedNetwork] = []

    private let storageKey = "wifisnap.saved.networks"

    init() {
        load()
    }

    func upsert(ssid: String, password: String) {
        if let idx = networks.firstIndex(where: { $0.ssid == ssid }) {
            networks[idx].password = password
            networks[idx].savedAt = Date()
        } else {
            networks.insert(SavedNetwork(ssid: ssid, password: password), at: 0)
        }
        persist()
    }

    func delete(at offsets: IndexSet) {
        networks.remove(atOffsets: offsets)
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
