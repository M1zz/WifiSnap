import Foundation

/// OCR로 읽은 SSID 문자열을 검증하고, '이 폰이 아는 와이파이 이름'으로 교정한다.
///
/// iOS는 주변 와이파이 목록을 앱에 제공하지 않는다(스캔은 NEHotspotHelper 특별 엔타이틀먼트 전용).
/// 그래서 '아는 이름'의 범위는 지금 연결된 SSID + 앱이 설정한 SSID + 앱에 저장된 SSID 뿐이고,
/// 그 밖의 이름이 실제로 존재하는지는 실제 연결(WifiConnector)로만 확인할 수 있다.
enum SSIDMatcher {

    /// SSID 규격(1~32바이트)과 상식에 맞는지 — OCR이 뱉은 쓰레기 값을 1차로 걸러낸다
    static func isPlausible(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              text.utf8.count <= 32,                                    // SSID 최대 32바이트
              text.rangeOfCharacter(from: .controlCharacters) == nil,   // 제어문자 = 인식 오류
              text.rangeOfCharacter(from: .alphanumerics) != nil        // 기호 덩어리는 이름이 아님
        else { return false }
        return true
    }

    /// 아는 이름 중 raw와 사실상 같은 것을 찾는다 (OCR 오탈자 교정용).
    /// 정규화 후 완전히 같으면 무조건 채택, 아니면 유사도가 threshold 이상일 때만.
    static func bestMatch(for raw: String, in known: [String], threshold: Double = 0.85) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var best: (ssid: String, score: Double)?
        for candidate in known {
            let score = similarity(text, candidate)
            if score >= 1.0 { return candidate }
            if score > (best?.score ?? 0) { best = (candidate, score) }
        }
        // 짧은 이름은 한 글자만 달라도 유사도가 높게 나와 오교정 위험이 크다
        guard let best, best.score >= threshold, max(text.count, best.ssid.count) >= 5 else { return nil }
        return best.ssid
    }

    /// 0.0~1.0. OCR이 자주 헷갈리는 글자(O/0, l/1, S/5…)를 같은 글자로 보고 비교한다.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(normalize(a)), y = Array(normalize(b))
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        if x == y { return 1 }
        return 1.0 - Double(levenshtein(x, y)) / Double(max(x.count, y.count))
    }

    // MARK: - Private

    /// OCR 혼동 글자표 (왼쪽을 오른쪽으로 접어서 비교)
    private static let confusions: [Character: Character] = [
        "0": "o", "1": "l", "i": "l", "|": "l",
        "5": "s", "8": "b", "2": "z", "6": "g", "9": "g"
    ]

    private static func normalize(_ text: String) -> String {
        var lowered = text.lowercased()
        lowered = lowered.replacingOccurrences(of: "rn", with: "m")   // rn → m 오인식
        lowered = lowered.replacingOccurrences(of: "vv", with: "w")   // vv → w 오인식
        return String(lowered.compactMap { ch -> Character? in
            // 구분자 표기 차이(공백/하이픈/언더바)는 무시
            if ch == " " || ch == "-" || ch == "_" { return nil }
            return confusions[ch] ?? ch
        })
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
