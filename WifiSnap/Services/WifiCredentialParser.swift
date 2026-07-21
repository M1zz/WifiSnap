import Foundation

struct WifiCredentials: Equatable {
    var ssid: String = ""
    var password: String = ""
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

    // 안내판에 흔하지만 자격증명이 아닌 문구
    private static let noiseWords = [
        "free", "zone", "guest", "무료", "환영", "welcome", "무선", "인터넷", "wifi존"
    ]

    // 값 가장자리에서 걷어낼 구분/기호 문자
    private static let junk = CharacterSet(charactersIn: " \t\r\n:：=＝|｜→⇒>》「」\"'`()[]（）/／-–—.,·•*")
    // 결합 라벨(ID/PW)의 값을 둘로 쪼갤 때 쓰는 구분자 (공백 포함)
    private static let comboDelimiters = CharacterSet(charactersIn: " \t/／,，·|｜")

    // MARK: - Public

    static func parse(lines: [String]) -> WifiCredentials {
        var result = WifiCredentials()
        var pendingKind: KeyKind? = nil     // "PW :"처럼 값이 다음 줄로 넘어간 경우
        var candidates: [String] = []       // 라벨 없는 줄 (마지막 추정용)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let hits = labelHits(in: line)

            // 직전 줄이 "라벨만" 있었던 경우 → 이 줄이 그 값
            if let pk = pendingKind {
                pendingKind = nil
                if hits.isEmpty {
                    assign(pk, cleanValue(line), to: &result)
                    continue
                }
                // 이 줄도 라벨이면 아래에서 새 라벨로 처리 (직전 라벨은 값 없이 버림)
            }

            // 라벨이 하나도 없으면 후보로만 모아두고 넘어감
            if hits.isEmpty {
                candidates.append(line)
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
                    assign(linePairs[0].kind, parts.first!, to: &result)
                    assign(linePairs[1].kind, parts.last!, to: &result)
                    continue
                }
            }

            for (kind, value) in linePairs {
                if value.isEmpty {
                    pendingKind = kind      // 값은 다음 줄에 있을 것
                } else {
                    assign(kind, value, to: &result)
                }
            }
        }

        fillMissing(&result, candidates: candidates)
        return result
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
        let pool = candidates.filter { c in
            c.count >= 4 &&
            !noiseWords.contains(where: { c.lowercased().contains($0) }) &&
            c != result.ssid && c != result.password
        }
        guard !pool.isEmpty else { return }

        if result.ssid.isEmpty && result.password.isEmpty {
            if pool.count == 1 {
                if pwScore(pool[0]) >= 2 { result.password = pool[0] } else { result.ssid = pool[0] }
                return
            }
            // 비번 점수 높은 순, 동점이면 뒤쪽 줄을 비번으로 (이름이 보통 위에 옴)
            let ranked = pool.enumerated().sorted { a, b in
                let sa = pwScore(a.element), sb = pwScore(b.element)
                return sa != sb ? sa > sb : a.offset > b.offset
            }.map(\.element)
            result.password = ranked.first!
            result.ssid = ranked.last!
        } else if result.password.isEmpty {
            if let best = pool.max(by: { pwScore($0) < pwScore($1) }), pwScore(best) >= 1 {
                result.password = best
            }
        } else if result.ssid.isEmpty {
            // 가장 아이디다운(비번 점수 낮은) 것
            if let best = pool.min(by: { pwScore($0) < pwScore($1) }) {
                result.ssid = best
            }
        }
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
