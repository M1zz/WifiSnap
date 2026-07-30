import Foundation

/// 사용자가 '설정 > Wi-Fi' 화면 캡처에서 가져온(또는 직접 적어 넣은) 와이파이 이름 목록.
///
/// iOS가 기기의 저장된 와이파이 목록을 앱에 주지 않아서, 사용자가 캡처로 알려준 이름을
/// 여기 보관했다가 SSID 선택 목록에 함께 보여준다. 비밀번호는 담지 않는다 — 이름뿐이다.
@MainActor
final class KnownSSIDStore: ObservableObject {
    @Published private(set) var ssids: [String] = []

    private let storageKey = "wifisnap.known.ssids"

    init() {
        load()
    }

    /// 이름들을 추가(중복은 건너뜀). 최근 추가한 것이 앞에 오도록 넣는다.
    func add(_ names: [String]) {
        var existing = Set(ssids.map { $0.lowercased() })
        let fresh = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && existing.insert($0.lowercased()).inserted }
        guard !fresh.isEmpty else { return }
        ssids.insert(contentsOf: fresh, at: 0)
        persist()
    }

    func remove(_ name: String) {
        ssids.removeAll { $0 == name }
        persist()
    }

    private func load() {
        guard let saved = UserDefaults.standard.stringArray(forKey: storageKey) else { return }
        ssids = saved
    }

    private func persist() {
        UserDefaults.standard.set(ssids, forKey: storageKey)
    }
}
