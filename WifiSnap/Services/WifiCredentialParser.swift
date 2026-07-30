import Foundation

struct WifiCredentials: Equatable {
    var ssid: String = ""
    var password: String = ""
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

    // MARK: - Public

    static func parse(lines: [String]) -> WifiScanResult {
        var result = WifiCredentials()
        var pendingKind: KeyKind? = nil     // "PW :"처럼 값이 다음 줄로 넘어간 경우
        var candidates: [String] = []       // 라벨 없는 줄 (마지막 추정용)
        var seenValues: [String] = []       // 등장한 모든 값 (SSID 후보 목록용)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let hits = labelHits(in: line)

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
                candidates.append(line)
                seenValues.append(cleanValue(line))
                continue
            }

            let linePairs = pairs(in: line, hits: hits)

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

    private struct Hit { let kind: KeyKind; let range: Range<String.Index> }

    /// 한 줄에서 유효한 라벨들의 위치를 찾는다.
    /// 유효 조건: 단어 경계가 맞고, (줄 맨 앞 라벨) 또는 (뒤에 명시적 구분자 :/= 가 옴).
    private static func labelHits(in line: String) -> [Hit] {
        var hits: [Hit] = []
        let firstContent = line.firstIndex(where: { !$0.isWhitespace }) ?? line.startIndex

        func scan(_ keys: [String], _ kind: KeyKind) {
            for key in keys {
                var from = line.startIndex
                while let r = line.range(of: key, options: .caseInsensitive, range: from..<line.endIndex) {
                    from = r.upperBound

                    // 앞 경계: 시작이거나 앞 글자가 문자(알파벳/한글)가 아님
                    let beforeOK = r.lowerBound == line.startIndex
                        || !line[line.index(before: r.lowerBound)].isLetter
                    // 뒤 경계: 끝이거나 뒤 글자가 문자가 아님 (단어 안에 박힌 키 배제)
                    let afterOK = r.upperBound == line.endIndex
                        || !line[r.upperBound].isLetter
                    guard beforeOK, afterOK else { continue }

                    // 라벨 자격: 줄 맨 앞이거나, 뒤에 명시적 구분자가 붙어야 함
                    let isLeading = r.lowerBound == firstContent
                    if isLeading || followedBySeparator(line, after: r.upperBound) {
                        hits.append(Hit(kind: kind, range: r))
                    }
                }
            }
        }
        scan(pwKeys, .pw)   // pw를 먼저 (id의 "id"가 "ssid"에 포함되는 등 우선순위)
        scan(idKeys, .id)

        // 위치순 정렬 후 겹치는 히트 제거(앞선 것 우선)
        hits.sort { $0.range.lowerBound < $1.range.lowerBound }
        var deduped: [Hit] = []
        for h in hits {
            if let last = deduped.last, h.range.lowerBound < last.range.upperBound { continue }
            deduped.append(h)
        }
        return deduped
    }

    /// 라벨 뒤(공백 건너뛰고)에 명시적 구분자(:/=)가 오는지
    private static func followedBySeparator(_ line: String, after index: String.Index) -> Bool {
        var i = index
        while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
        guard i < line.endIndex else { return false }
        return ":：=＝".contains(line[i])
    }

    /// 히트들 사이 구간을 각 라벨의 값으로 잘라낸다.
    private static func pairs(in line: String, hits: [Hit]) -> [(kind: KeyKind, value: String)] {
        var out: [(KeyKind, String)] = []
        for (i, h) in hits.enumerated() {
            let start = h.range.upperBound
            let end = (i + 1 < hits.count) ? hits[i + 1].range.lowerBound : line.endIndex
            out.append((h.kind, cleanValue(String(line[start..<end]))))
        }
        return out
    }

    // MARK: - 값 정리 / 배정

    private static func cleanValue(_ text: String) -> String {
        text.trimmingCharacters(in: junk)
    }

    private static func assign(_ kind: KeyKind, _ value: String, to result: inout WifiCredentials) {
        guard !value.isEmpty else { return }
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
