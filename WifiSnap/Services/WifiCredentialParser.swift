import Foundation

struct WifiCredentials: Equatable {
    var ssid: String = ""
    var password: String = ""
}

extension Character {
    /// 한글(음절·자모)인지 — 라벨의 조사 처리와 안내 문장 판별에 쓴다.
    var isHangul: Bool {
        unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)      // 음절
                || (0x1100...0x11FF).contains(scalar.value)   // 자모
                || (0x3130...0x318F).contains(scalar.value)   // 호환 자모
        }
    }
}

/// 사진 한 장의 인식 결과. 파서의 '최선의 추측'과 함께,
/// 추측이 틀렸을 때 사용자가 바로 고를 수 있도록 SSID 후보들을 함께 돌려준다.
struct WifiScanResult: Equatable {
    var credentials = WifiCredentials()
    /// SSID로 쓸 만한 후보 (추천순). 비어 있지 않으면 첫 항목이 credentials.ssid.
    var ssidCandidates: [String] = []
    /// 사진에서 읽은 값 조각 전부 (사진에 나온 순서).
    /// 추측이 틀렸을 때 아이디·비밀번호 칸으로 끌어다 놓는 퍼즐 조각으로 쓴다.
    var tokens: [String] = []
}

/// OCR로 읽은 줄들에서 ID(SSID)와 PW를 최대한 다양한 표기로 찾아내는 파서.
///
/// 지원 패턴 예시:
/// - "ID : JEONHO-WIFI-5G", "PW: 12345678", "비밀번호 abcd"
/// - "SSID=Cafe", "네트워크 - MyWifi", "PW | 1234"
/// - 라벨만 있고 값이 다음 줄에 있는 경우 ("PW :" ↵ "1234")
/// - 한 줄에 둘 다: "ID: cafe  PW: 1234", "아이디 cafe 비밀번호 1234"
/// - 결합 라벨: "ID/PW : cafe / 1234"
/// - 라벨이 전혀 없을 때: 비밀번호/아이디처럼 생긴 줄을 점수로 추정
enum WifiCredentialParser {

    enum KeyKind { case id, pw }

    // 라벨 사전. 경계 규칙이 오탐(단어 안에 박힌 키)을 걸러주므로 짧은 키도 안전.
    private static let idKeys = [
        "ssid", "네트워크이름", "네트워크명", "네트워크", "와이파이이름", "wifi이름", "wifi명",
        "무선네트워크", "와이파이", "wi-fi", "wifi", "아이디", "network", "name", "id"
    ]
    private static let pwKeys = [
        "password", "passwd", "패스워드", "비밀번호", "패스", "pass", "비번", "암호",
        "p/w", "pwd", "pw", "key"
    ]

    // 안내판에 흔하지만 자격증명이 아닌 장식 문구
    private static let noiseWords = [
        "free", "zone", "guest", "무료", "환영", "welcome", "무선", "인터넷",
        "wifi존", "wi-fi", "wifi", "와이파이"
    ]

    /// 장식 문구뿐인 줄인지 — 장식 단어를 걷어냈을 때 남는 글자가 없으면 잡음("FREE WIFI", "무료").
    /// 부분 일치로 판단하면 "CAFE_GUEST", "KT_WiFi", "welcome1234" 같은 진짜 값까지 사라진다.
    private static func isNoise(_ text: String) -> Bool {
        var rest = text.lowercased()
        for word in noiseWords {
            rest = rest.replacingOccurrences(of: word, with: " ")
        }
        return rest.rangeOfCharacter(from: .alphanumerics) == nil
    }

    /// 장식 문구를 뺀 후보를 우선 쓰되, 그러면 남는 게 없을 땐 장식 문구라도 쓴다.
    /// (안내판에 "FreeWiFi" 한 줄만 있고 그게 진짜 이름인 경우를 잃지 않으려고)
    private static func preferring(_ pool: [String]) -> [String] {
        let clean = pool.filter { !isNoise($0) }
        return clean.isEmpty ? pool : clean
    }

    // 값 가장자리에서 걷어낼 구분/기호 문자
    private static let junk = CharacterSet(charactersIn: " \t\r\n:：=＝|｜→⇒>》「」\"'`()[]（）/／-–—.,·•*")
    // 결합 라벨(ID/PW)의 값을 둘로 쪼갤 때 쓰는 구분자 (공백 포함)
    private static let comboDelimiters = CharacterSet(charactersIn: " \t/／,，·|｜")

    /// 구분자(:/=) 없이 줄 가운데에 나와도 라벨로 인정할 키.
    ///
    /// 안내판은 "CAFE_MOMO PW 1234"처럼 구분자를 생략하는 일이 흔하다. 다만 아무 키나 그렇게
    /// 인정하면 "Free WiFi zone", "Guest Network" 같은 이름이 라벨로 오인되므로,
    /// 다른 뜻으로 쓰일 일이 거의 없는 키만 넣는다.
    private static let looseKeys: Set<String> = [
        "password", "passwd", "pwd", "pw", "p/w", "ssid",
        "비밀번호", "패스워드", "패스", "비번", "암호", "아이디",
        "네트워크이름", "네트워크명", "와이파이이름", "wifi이름", "wifi명"
    ]

    /// 한글 라벨에 달라붙는 조사 — "비밀번호는 1234"의 '는'을 라벨의 일부로 본다.
    private static let hangulParticles: Set<Character> = [
        "는", "은", "이", "가", "를", "을", "도", "와", "과", "의", "로", "에"
    ]

    /// 값 뒤에 붙는 안내 문장의 꼬리 — "momo1234 입력", "12341234 입니다"에서 걷어낸다.
    private static let sentenceTails: Set<String> = [
        "입니다", "입니당", "이에요", "예요", "예요.", "됩니다", "입력", "선택", "사용",
        "접속", "연결", "하세요", "해주세요", "확인", "참고", "이용"
    ]

    // MARK: - Public

    static func parse(lines: [String]) -> WifiScanResult {
        var result = WifiCredentials()
        var pendingKind: KeyKind? = nil     // "PW :"처럼 값이 다음 줄로 넘어간 경우
        var candidates: [String] = []       // 라벨 없는 줄 (마지막 추정용)
        var seenValues: [String] = []       // 등장한 모든 값 (SSID 후보 목록용)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let chars = Array(line)
            let hits = labelHits(in: chars)

            // "CAFE_MOMO (ID)"처럼 라벨이 값 뒤에 붙은 표기는 여기서 먼저 풀어낸다
            if hits.isEmpty || hits.allSatisfy({ $0.start > 0 }), let tail = trailingLabel(in: line) {
                pendingKind = nil
                seenValues.append(tail.value)
                assign(tail.kind, tail.value, to: &result)
                continue
            }

            // 직전 줄이 "라벨만" 있었던 경우 → 이 줄이 그 값
            if let pk = pendingKind {
                pendingKind = nil
                if hits.isEmpty {
                    let value = cleanValue(line)
                    seenValues.append(value)
                    assign(pk, value, to: &result)
                    continue
                }
                // 이 줄도 라벨이면 아래에서 새 라벨로 처리 (직전 라벨은 값 없이 버림)
            }

            // 라벨이 하나도 없으면 후보로만 모아두고 넘어감
            if hits.isEmpty {
                let values = candidateValues(in: line)
                candidates.append(contentsOf: values)
                seenValues.append(contentsOf: values.map(cleanValue))
                continue
            }

            // 라벨 앞에 놓인 값도 잃지 않는다 ("CAFE_MOMO PW 1234" 의 이름)
            if let first = hits.first, first.start > 0 {
                let prefix = cleanValue(String(chars[0..<first.start]))
                if !prefix.isEmpty, !isPhrase(prefix) {
                    candidates.append(prefix)
                    seenValues.append(prefix)
                }
            }

            let linePairs = pairs(in: chars, hits: hits)

            // 결합 라벨 "ID/PW: cafe / 1234": 앞 값이 비고 뒤 값에 구분자가 있으면 둘로 분할
            if linePairs.count == 2,
               linePairs[0].value.isEmpty,
               linePairs[1].value.rangeOfCharacter(from: comboDelimiters) != nil {
                let parts = linePairs[1].value
                    .components(separatedBy: comboDelimiters)
                    .map { $0.trimmingCharacters(in: junk) }
                    .filter { !$0.isEmpty }
                if parts.count >= 2 {
                    seenValues.append(contentsOf: [parts.first!, parts.last!])
                    assign(linePairs[0].kind, parts.first!, to: &result)
                    assign(linePairs[1].kind, parts.last!, to: &result)
                    continue
                }
            }

            for (kind, value) in linePairs {
                if value.isEmpty {
                    pendingKind = kind      // 값은 다음 줄에 있을 것
                } else {
                    seenValues.append(value)
                    assign(kind, value, to: &result)
                }
            }
        }

        fillMissing(&result, candidates: candidates)
        return WifiScanResult(
            credentials: result,
            ssidCandidates: rankSSIDCandidates(seenValues, result: result),
            tokens: tokenPool(seenValues)
        )
    }

    /// 퍼즐 조각 풀 — 사진에 나온 순서 그대로, 값으로 쓸 만한 것만.
    /// 사진의 배치와 순서가 같아야 사용자가 어떤 조각인지 알아본다.
    private static func tokenPool(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: junk) }
            // 퍼즐은 사용자의 탈출구이므로 장식 문구도 남긴다 — 그게 진짜 이름일 수도 있다
            .filter { SSIDMatcher.isPlausible($0) && seen.insert($0).inserted }
    }

    /// 사진에서 나온 값들 중 SSID로 쓸 만한 것을 추천순으로 정렬한다.
    /// 파서가 고른 값을 맨 앞에 두되, 그게 틀렸을 때 사용자가 바로 다른 걸 고를 수 있게 한다.
    private static func rankSSIDCandidates(_ values: [String], result: WifiCredentials) -> [String] {
        var seen = Set<String>()
        let pool = values
            .map { $0.trimmingCharacters(in: junk) }
            .filter { SSIDMatcher.isPlausible($0) && $0 != result.password && seen.insert($0).inserted }

        // 아이디다움 점수 순. 동점이면 사진에서 먼저 나온 줄 우선.
        var ranked = pool.enumerated()
            .sorted { a, b in
                let sa = ssidRank(a.element), sb = ssidRank(b.element)
                return sa != sb ? sa > sb : a.offset < b.offset
            }
            .map(\.element)

        // 파서가 확정한 SSID는 항상 맨 앞
        if !result.ssid.isEmpty {
            ranked.removeAll { $0 == result.ssid }
            ranked.insert(result.ssid, at: 0)
        }
        return Array(ranked.prefix(6))
    }

    // MARK: - 라벨 탐지

    /// 원문 문자 인덱스로 표현한 라벨 위치 (end는 미포함)
    private struct Hit { let kind: KeyKind; let start: Int; let end: Int }

    /// 한 줄에서 유효한 라벨들의 위치를 찾는다.
    ///
    /// 매칭은 **공백을 지운 사본** 위에서 한다. 안내판의 한글 라벨은 띄어쓰기가 제각각이라
    /// ("와이파이 이름", "비밀 번호") 원문 그대로 찾으면 사전에 있는 키와 어긋난다.
    /// 찾은 위치는 원문 인덱스로 되돌려, 값에 들어 있는 공백("1234 5678")은 그대로 살린다.
    ///
    /// 유효 조건: 단어 경계가 맞고, 아래 중 하나.
    /// - 줄 맨 앞 라벨
    /// - 뒤에 명시적 구분자(:/=)가 옴
    /// - looseKeys에 속하고, 앞뒤가 공백으로 끊긴 채 값이 이어짐 ("CAFE_MOMO PW 1234")
    private static func labelHits(in chars: [Character]) -> [Hit] {
        // 공백을 지운 소문자 사본과, 그 각 글자가 원문 어디였는지의 지도
        var condensed: [Character] = []
        var origin: [Int] = []
        for (index, character) in chars.enumerated() where !character.isWhitespace {
            condensed.append(Character(String(character).lowercased().first.map(String.init) ?? String(character)))
            origin.append(index)
        }
        guard !condensed.isEmpty else { return [] }
        let firstContent = origin[0]

        var hits: [Hit] = []

        func scan(_ keys: [String], _ kind: KeyKind) {
            for key in keys {
                let pattern = Array(key.lowercased())
                guard pattern.count <= condensed.count else { continue }
                for start in 0...(condensed.count - pattern.count) {
                    guard Array(condensed[start..<(start + pattern.count)]) == pattern else { continue }

                    // 한글 라벨에 달라붙은 조사는 라벨의 일부로 흡수한다 ("비밀번호는 1234")
                    var end = start + pattern.count
                    if pattern.last?.isHangul == true {
                        while end < condensed.count, hangulParticles.contains(condensed[end]),
                              end - (start + pattern.count) < 2 {
                            end += 1
                        }
                    }

                    let originStart = origin[start]
                    let originEnd = origin[end - 1] + 1
                    // 단어 경계는 반드시 원문에서 본다. 공백을 지운 사본에서 판단하면
                    // "CAFE_MOMO PW 1234"의 PW가 앞 글자에 붙은 것으로 오인돼 라벨을 놓친다.
                    let beforeOK = originStart == 0 || !chars[originStart - 1].isLetter
                    let afterOK = originEnd >= chars.count || !chars[originEnd].isLetter
                    guard beforeOK, afterOK else { continue }
                    let isLeading = originStart == firstContent
                    let loose = looseKeys.contains(key)
                        && separatedBefore(chars, at: originStart)
                        && valueFollows(chars, from: originEnd)

                    if isLeading || followedBySeparator(chars, from: originEnd) || loose {
                        hits.append(Hit(kind: kind, start: originStart, end: originEnd))
                    }
                }
            }
        }
        scan(pwKeys, .pw)   // pw를 먼저 (id의 "id"가 "ssid"에 포함되는 등 우선순위)
        scan(idKeys, .id)

        // 위치순 정렬 후 겹치는 히트 제거(앞선 것, 같은 자리면 긴 것 우선)
        hits.sort { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }
        var deduped: [Hit] = []
        for hit in hits {
            if let last = deduped.last, hit.start < last.end { continue }
            deduped.append(hit)
        }
        return deduped
    }

    /// 라벨 뒤(공백 건너뛰고)에 명시적 구분자(:/=)가 오는지
    private static func followedBySeparator(_ chars: [Character], from index: Int) -> Bool {
        var i = index
        while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
        guard i < chars.count else { return false }
        return ":：=＝".contains(chars[i])
    }

    /// 라벨 앞이 줄 시작이거나 공백으로 끊겨 있는지 (단어 꼬리에 우연히 걸린 키 배제)
    private static func separatedBefore(_ chars: [Character], at index: Int) -> Bool {
        index == 0 || chars[index - 1].isWhitespace
    }

    /// 라벨 뒤에 공백 하나를 두고 값처럼 생긴 글자가 이어지는지
    private static func valueFollows(_ chars: [Character], from index: Int) -> Bool {
        guard index < chars.count, chars[index].isWhitespace else { return false }
        var i = index
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        guard i < chars.count else { return false }
        return chars[i].isLetter || chars[i].isNumber
    }

    /// 히트들 사이 구간을 각 라벨의 값으로 잘라낸다.
    private static func pairs(in chars: [Character], hits: [Hit]) -> [(kind: KeyKind, value: String)] {
        var out: [(KeyKind, String)] = []
        for (i, hit) in hits.enumerated() {
            let start = hit.end
            let end = (i + 1 < hits.count) ? hits[i + 1].start : chars.count
            guard start <= end else { continue }
            out.append((hit.kind, cleanValue(String(chars[start..<end]))))
        }
        return out
    }

    /// 값 뒤에 라벨이 괄호로 붙은 표기 ("CAFE_MOMO (ID)")를 값과 종류로 되돌린다.
    private static func trailingLabel(in line: String) -> (kind: KeyKind, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(where: { $0 == "(" || $0 == "[" || $0 == "（" }),
              trimmed.last == ")" || trimmed.last == "]" || trimmed.last == "）" else { return nil }

        let inside = String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let value = cleanValue(String(trimmed[trimmed.startIndex..<open]))
        guard !value.isEmpty else { return nil }

        if pwKeys.contains(inside) { return (.pw, value) }
        if idKeys.contains(inside) { return (.id, value) }
        return nil
    }

    // MARK: - 값 정리 / 배정

    /// 값에서 가장자리 기호를 걷어내고, 눈에 안 보이는 문자(제로폭·전각)까지 정리한다.
    /// 여기서 걸러두지 않으면 화면상 똑같아 보이는 값으로 연결만 조용히 실패한다.
    /// 안내 문장의 꼬리("… 입력", "… 입니다")도 함께 떼어낸다.
    private static func cleanValue(_ text: String) -> String {
        strippingSentenceTails(SSIDMatcher.sanitize(text).trimmingCharacters(in: junk))
    }

    /// 값 앞뒤에 붙은 안내 문구를 걷어낸다 ("momo1234 입력" → "momo1234").
    /// 값이 통째로 한글 문구면 건드리지 않는다 — 그건 값이 아니라 문장이고, 따로 걸러진다.
    private static func strippingSentenceTails(_ value: String) -> String {
        var parts = value.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return value }

        /// 떼어내고 남은 것이 값처럼 보일 때만 뗀다. 남는 게 또 한글 낱말뿐이면
        /// 애초에 값이 아니라 문장이므로, 문장의 일부만 남겨 값인 척하게 두면 안 된다.
        func keepsValue(_ remaining: [String]) -> Bool {
            remaining.contains { part in
                part.contains { $0.isNumber || ($0.isLetter && !$0.isHangul) }
            }
        }
        while parts.count > 1, let last = parts.last,
              sentenceTails.contains(last.trimmingCharacters(in: junk)),
              keepsValue(Array(parts.dropLast())) {
            parts.removeLast()
        }
        while parts.count > 1, let first = parts.first,
              sentenceTails.contains(first.trimmingCharacters(in: junk)),
              keepsValue(Array(parts.dropFirst())) {
            parts.removeFirst()
        }
        return parts.joined(separator: " ").trimmingCharacters(in: junk)
    }

    /// 자격증명 값이 아니라 안내 문장인지 — 한글 낱말이 둘 이상 이어진 덩어리("접속 방법").
    /// 한 낱말짜리 한글 이름("우리집와이파이")은 실제 SSID일 수 있으므로 값으로 인정한다.
    private static func isPhrase(_ value: String) -> Bool {
        let parts = value.split(separator: " ")
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            part.contains(where: { $0.isHangul }) && !part.contains(where: { $0.isNumber })
        }
    }

    /// 라벨 없는 줄에서 값으로 쓸 만한 조각을 뽑는다.
    ///
    /// "1. 설정에서 CAFE_MOMO 선택"처럼 안내 문장 안에 값이 섞여 있으면 줄 전체는 값이 될 수 없다.
    /// 한글 문장 안에 라틴·숫자 낱말이 섞여 있을 때만 그 낱말을 따로 떼어 후보로 삼는다
    /// (한글이 없는 줄은 "CAFE MOMO"처럼 이름 자체일 수 있으므로 통째로 둔다).
    private static func candidateValues(in line: String) -> [String] {
        let hasHangul = line.contains { $0.isHangul }
        guard hasHangul else { return [line] }

        let words = line.split(separator: " ").map { String($0).trimmingCharacters(in: junk) }
        let latinWords = words.filter { word in
            word.count >= 4
                && !word.contains(where: { $0.isHangul })
                && word.rangeOfCharacter(from: .alphanumerics) != nil
        }
        return latinWords.isEmpty ? [line] : latinWords
    }

    private static func assign(_ kind: KeyKind, _ value: String, to result: inout WifiCredentials) {
        guard !value.isEmpty, !isPhrase(value) else { return }
        switch kind {
        case .id: if result.ssid.isEmpty { result.ssid = value }
        case .pw: if result.password.isEmpty { result.password = value }
        }
    }

    // MARK: - 라벨 없이 추정

    /// 라벨로 못 채운 칸을 "비밀번호처럼/아이디처럼 생겼는지"로 채운다.
    private static func fillMissing(_ result: inout WifiCredentials, candidates: [String]) {
        let usable = candidates.filter { c in
            c.count >= 4 && c != result.ssid && c != result.password
        }
        guard !usable.isEmpty else { return }

        if result.ssid.isEmpty && result.password.isEmpty {
            if usable.count == 1 {
                if pwScore(usable[0]) >= 2 { result.password = usable[0] } else { result.ssid = usable[0] }
                return
            }
            // 비밀번호를 먼저 고르고, 남은 것 중에서 아이디를 고른다
            let password = best(in: preferring(usable), by: passwordRank, preferLaterLine: true)
            result.password = password
            let rest = usable.filter { $0 != password }
            result.ssid = best(in: preferring(rest.isEmpty ? usable : rest),
                               by: ssidRank, preferLaterLine: false)
        } else if result.password.isEmpty {
            let candidate = best(in: preferring(usable), by: passwordRank, preferLaterLine: true)
            if pwScore(candidate) >= 1 { result.password = candidate }
        } else if result.ssid.isEmpty {
            result.ssid = best(in: preferring(usable), by: ssidRank, preferLaterLine: false)
        }
    }

    /// 점수가 가장 높은 값. 동점이면 비밀번호는 아래쪽 줄, 아이디는 위쪽 줄을 고른다
    /// (안내판은 보통 이름이 위, 비밀번호가 아래에 온다).
    private static func best(in pool: [String],
                             by score: (String) -> Int,
                             preferLaterLine: Bool) -> String {
        pool.enumerated().max { a, b in
            let sa = score(a.element), sb = score(b.element)
            if sa != sb { return sa < sb }
            return preferLaterLine ? a.offset < b.offset : a.offset > b.offset
        }!.element
    }

    /// 한글·한자·가나가 섞였는지. 와이파이 이름과 비밀번호는 라틴 문자·숫자가 압도적으로 많다.
    private static func hasNonLatinScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)      // 한글 음절
                || (0x1100...0x11FF).contains(scalar.value)   // 한글 자모
                || (0x3130...0x318F).contains(scalar.value)   // 한글 호환 자모
                || (0x3040...0x30FF).contains(scalar.value)   // 가나
                || (0x4E00...0x9FFF).contains(scalar.value)   // 한자
        }
    }

    /// 영문 우선 가산점. pwScore 범위(대략 ±6)보다 크게 잡아 라틴 문자 값이 항상 앞서게 한다.
    /// 후보가 전부 한글이면 가산점이 모두에게 없으므로 그중에서 정상적으로 고른다.
    private static let latinBonus = 10

    private static func latinScore(_ text: String) -> Int {
        hasNonLatinScript(text) ? 0 : latinBonus
    }

    /// 비밀번호 후보 점수 (클수록 비밀번호다움)
    private static func passwordRank(_ text: String) -> Int {
        pwScore(text) + latinScore(text)
    }

    /// 아이디 후보 점수 (클수록 아이디다움)
    private static func ssidRank(_ text: String) -> Int {
        -pwScore(text) + latinScore(text)
    }

    /// 값이 비밀번호처럼 보일수록 큰 점수 (아이디처럼 보이면 낮거나 음수)
    private static func pwScore(_ text: String) -> Int {
        let hasSpace = text.contains(" ")
        let hasSeparator = text.rangeOfCharacter(from: CharacterSet(charactersIn: "-_")) != nil
        let hasDigit = text.rangeOfCharacter(from: .decimalDigits) != nil
        let hasLetter = text.rangeOfCharacter(from: .letters) != nil
        let isAllDigits = hasDigit && !hasLetter
            && text.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil

        var score = 0
        if hasSpace { score -= 3 }                                   // 공백 있으면 SSID 쪽
        if hasSeparator { score -= 2 }                               // -, _ 는 SSID 표기
        if isAllDigits && text.count >= 6 { score += 3 }             // 숫자만 = 전형적 비번
        if hasLetter && hasDigit && !hasSpace && !hasSeparator {     // 영숫자 혼합 토큰
            score += 2
        }
        if text.count >= 8 { score += 1 }
        if text.count <= 5 { score -= 1 }
        return score
    }
}
