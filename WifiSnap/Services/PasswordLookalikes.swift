import Foundation

/// 사진에서 비밀번호를 읽을 때 서로 헷갈리기 쉬운 글자(0·O, 1·l·I, 5·S …)를
/// 한 글자씩 바꿔 본 후보. 연결에 실패했을 때 "이 글자일 수도 있어요"로 보여 준다.
///
/// 연결을 시도할 때마다 iOS 확인 창이 뜨므로 후보를 다 돌려 볼 수는 없다.
/// 그래서 앞뒤 글자와 어울리지 않는 글자(숫자 사이의 S, 소문자 사이의 O)를 바꾼 것부터 몇 개만 고른다.
enum PasswordLookalikes {

    /// 모양이 닮아 서로 잘못 읽히는 글자 묶음.
    /// c·o·s·v·w·x·z처럼 대문자와 소문자의 모양이 같은 글자는 대소문자 자체가 헷갈린다.
    private static let groups: [[Character]] = [
        ["0", "O", "o"], ["1", "l", "I"], ["5", "S", "s"], ["8", "B"], ["2", "Z", "z"],
        ["9", "g", "q"], ["6", "b"],
        ["c", "C"], ["k", "K"], ["p", "P"], ["u", "U"], ["v", "V"], ["w", "W"], ["x", "X"]
    ]

    private static let alternatives: [Character: [Character]] = {
        var map: [Character: [Character]] = [:]
        for group in groups {
            for character in group {
                map[character, default: []] += group.filter { $0 != character }
            }
        }
        return map
    }()

    /// 그럴듯한 순서로 고른 후보 (원래 값 제외). 앞뒤와 더 잘 어울리게 되는 것만 낸다.
    static func suggestions(for password: String, limit: Int = 3) -> [String] {
        let characters = Array(password)
        var scored: [(text: String, gain: Int, index: Int)] = []

        for (index, character) in characters.enumerated() {
            guard let options = alternatives[character] else { continue }
            let neighbors = [index - 1, index + 1]
                .filter { characters.indices.contains($0) }
                .map { characters[$0] }
            let before = fit(character, neighbors)
            for option in options {
                let gain = fit(option, neighbors) - before
                guard gain > 0 else { continue }
                var changed = characters
                changed[index] = option
                scored.append((String(changed), gain, index))
            }
        }

        var seen = Set<String>()
        return scored
            .sorted { $0.gain != $1.gain ? $0.gain > $1.gain : $0.index < $1.index }
            .map(\.text)
            .filter { seen.insert($0).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// 이웃 중 같은 갈래(숫자 / 대문자 / 소문자)인 글자 수
    private static func fit(_ character: Character, _ neighbors: [Character]) -> Int {
        neighbors.filter { kind(of: $0) == kind(of: character) && kind(of: $0) != .other }.count
    }

    private enum Kind { case digit, upper, lower, other }

    private static func kind(of character: Character) -> Kind {
        if character.isNumber { return .digit }
        if character.isUppercase { return .upper }
        if character.isLowercase { return .lower }
        return .other
    }
}

/// "그 와이파이에 붙지 못했어요"로 실패한 뒤 다시 해 볼 것들.
///
/// 이름과 비밀번호 중 무엇이 틀렸는지는 iOS가 알려 주지 않는다. 그래서 둘 다의 후보를 내고,
/// 이미 해 본 값은 다시 권하지 않는다.
struct ConnectRetry {
    /// 실패한 이름. nil이면 실패한 적이 없다.
    private(set) var failedSSID: String?
    private var nameCandidates: [String] = []
    private var triedNames: Set<String> = []

    /// 비밀번호 후보를 만드는 기준 — 사진에서 처음 읽은 값
    private var passwordBase: String?
    private var triedPasswords: Set<String> = []
    private var lastFailedPassword: String?

    var hasFailed: Bool { failedSSID != nil }

    /// - Parameter nameSuggestions: 연결기가 아직 시도하지 않은 대소문자 표기들
    mutating func recordFailure(ssid: String, password: String, nameSuggestions: [String]) {
        failedSSID = ssid
        triedNames.insert(ssid)
        // 새로 받은 후보를 앞에, 전에 받아 둔 것 중 아직 안 해 본 것을 뒤에
        nameCandidates = (nameSuggestions + nameCandidates).reduce(into: []) { list, name in
            if !list.contains(name) { list.append(name) }
        }

        guard !password.isEmpty else { return }
        // 권해 준 후보로 또 실패했으면 기준은 그대로 두고, 손으로 다른 값을 쳤으면 그 값이 새 기준
        let fromSuggestion = passwordBase.map {
            triedPasswords.contains(password) || PasswordLookalikes.suggestions(for: $0, limit: .max).contains(password)
        } ?? false
        if !fromSuggestion {
            passwordBase = password
            triedPasswords = []
        }
        triedPasswords.insert(password)
        lastFailedPassword = password
    }

    /// 대소문자만 다른 이름 후보 (지금 칸의 값과 해 본 값은 뺀다)
    func nameSuggestions(current: String) -> [String] {
        Array(nameCandidates.filter { $0 != current && !triedNames.contains($0) }.prefix(3))
    }

    /// 지금 칸의 비밀번호가 방금 실패한 그 값일 때만 후보를 낸다 (손으로 고치기 시작하면 거둔다)
    func passwordSuggestions(current: String) -> [String] {
        guard let passwordBase, !current.isEmpty, current == lastFailedPassword else { return [] }
        return Array(PasswordLookalikes.suggestions(for: passwordBase, limit: .max)
            .filter { !triedPasswords.contains($0) }
            .prefix(3))
    }
}
