import Foundation

/// OCR로 읽은 SSID 문자열을 검증하고, '이 폰이 아는 와이파이 이름'으로 교정한다.
///
/// iOS는 주변 와이파이 목록을 앱에 제공하지 않는다(스캔은 NEHotspotHelper 특별 엔타이틀먼트 전용).
/// 그래서 '아는 이름'의 범위는 지금 연결된 SSID + 앱이 설정한 SSID + 앱에 저장된 SSID 뿐이고,
/// 그 밖의 이름이 실제로 존재하는지는 실제 연결(WifiConnector)로만 확인할 수 있다.
enum SSIDMatcher {

    /// 눈에는 안 보이지만 iOS에게는 '다른 이름'이 되는 차이를 없앤다.
    ///
    /// OCR·복사붙여넣기로 제로폭 문자, 전각 영숫자(ＳＫ), 스마트 따옴표가 섞여 들어오면
    /// 화면상으로는 똑같은 값인데 연결만 조용히 실패한다 — 가장 찾기 어려운 실패 원인이라
    /// 연결 직전에 반드시 통과시킨다.
    ///
    /// - Parameter foldLookalikes: 전각·스마트 따옴표를 평범한 글자로 접을지.
    ///   OCR·붙여넣기처럼 값이 '옮겨 적히면서 변형됐을' 때만 참이어야 한다.
    ///   사용자가 직접 친 이름은 그 자체가 정답이라 접으면 오히려 망가진다 —
    ///   아이폰 이름의 스마트 어포스트로피(Leeo’s iPhone)를 ASCII '로 바꾸면
    ///   실제로 방송되는 SSID와 한 바이트가 달라져 스캔한 폰이 네트워크를 못 찾는다.
    static func sanitize(_ raw: String, foldLookalikes: Bool = true) -> String {
        var text = raw
        if foldLookalikes {
            // 전각 영숫자·기호가 실제로 섞였을 때만 반각으로 접는다.
            // 조건 없이 변환하면 한글·가나 표기까지 건드릴 수 있다.
            if text.unicodeScalars.contains(where: { (0xFF01...0xFF5E).contains($0.value) }) {
                text = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
            }
            for (from, to) in punctuationFolds {
                text = text.replacingOccurrences(of: from, with: to)
            }
        }
        // 보이지 않는 문자는 어느 경로로 들어왔든 사용자가 의도한 것이 아니다
        text = String(String.UnicodeScalarView(text.unicodeScalars.filter { !isInvisible($0) }))
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 대소문자만 다른 그럴듯한 표기들 (원본은 제외, 추천순).
    /// OCR은 글자 모양은 맞춰도 대소문자를 자주 틀리는데(WiFi→Wifi), SSID는 대소문자를 구분해서
    /// 한 글자만 달라도 '그런 이름의 네트워크는 없음'이 된다.
    static func caseVariants(of raw: String) -> [String] {
        let text = sanitize(raw)
        guard text.rangeOfCharacter(from: .letters) != nil else { return [] }
        var seen: Set<String> = [text]
        return [brandCanonical(text), text.uppercased(), text.lowercased()]
            .filter { seen.insert($0).inserted }
    }

    /// 공유기 라벨에 흔한 토큰을 정식 표기로 되돌린 이름
    static func brandCanonical(_ text: String) -> String {
        var result = text
        for spelling in brandSpellings {
            result = replacing(spelling.pattern,
                               with: spelling.canonical,
                               in: result,
                               wholeTokenOnly: spelling.wholeToken)
        }
        return result
    }

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

    // MARK: - Private (정리·표기)

    private static let punctuationFolds: [(String, String)] = [
        ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
        ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{2212}", "-"), ("\u{00A0}", " ")
    ]

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B...0x200F,   // 제로폭 공백·결합자·방향 표시
             0x202A...0x202E,   // 방향 재정의
             0x2060...0x2064,   // word joiner 계열
             0xFEFF:            // BOM
            return true
        default:
            return scalar.properties.generalCategory == .control
        }
    }

    /// 국내 공유기 이름에 흔한 토큰의 정식 표기.
    /// wholeToken=true는 짧아서 다른 단어 안에 우연히 박히기 쉬운 것(kt가 pocket 안에 들어가는 등)이라
    /// 앞뒤가 영숫자가 아닐 때만 바꾼다.
    private static let brandSpellings: [(pattern: String, canonical: String, wholeToken: Bool)] = [
        ("wi-fi", "Wi-Fi", false),
        ("wifi", "WiFi", false),
        ("giga", "GIGA", false),
        ("iptime", "ipTIME", false),
        ("olleh", "olleh", false),
        ("wlan", "WLAN", false),
        ("kt", "KT", true),
        ("sk", "SK", true),
        ("skb", "SKB", true),
        ("lg", "LG", true)
    ]

    private static func replacing(_ pattern: String,
                                  with canonical: String,
                                  in text: String,
                                  wholeTokenOnly: Bool) -> String {
        var result = text
        var from = result.startIndex
        while let range = result.range(of: pattern, options: .caseInsensitive, range: from..<result.endIndex) {
            func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }
            let boundedOK = !wholeTokenOnly || (
                (range.lowerBound == result.startIndex
                    || !isWordChar(result[result.index(before: range.lowerBound)]))
                && (range.upperBound == result.endIndex
                    || !isWordChar(result[range.upperBound]))
            )
            guard boundedOK else {
                from = range.upperBound
                continue
            }
            result.replaceSubrange(range, with: canonical)
            // 치환 후에는 인덱스가 무효해지므로 오프셋으로 다시 잡는다
            let offset = result.distance(from: result.startIndex, to: range.lowerBound) + canonical.count
            from = result.index(result.startIndex, offsetBy: offset)
        }
        return result
    }

    // MARK: - Private (유사도)

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
