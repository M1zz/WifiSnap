import Foundation

struct WifiCredentials: Equatable {
    var ssid: String = ""
    var password: String = ""
}

/// OCR로 읽은 줄들에서 ID(SSID)와 PW를 찾아내는 파서
/// "ID : JEONHO-WIFI-5G", "PW: 12345678", "비밀번호 abcd" 등 다양한 표기를 처리
enum WifiCredentialParser {

    private static let idKeys = ["ssid", "id", "아이디", "네트워크", "network", "name", "wifi명", "와이파이"]
    private static let pwKeys = ["password", "passwd", "pass", "pw", "p/w", "비밀번호", "비번", "암호", "key"]
    // 안내판에 흔히 있지만 자격증명이 아닌 문구
    private static let noiseWords = ["free", "zone", "guest", "무료", "환영", "welcome"]

    static func parse(lines: [String]) -> WifiCredentials {
        var result = WifiCredentials()
        var pendingKey: String? = nil   // "PW :" 처럼 값이 다음 줄로 넘어간 경우

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // 이전 줄이 키만 있었던 경우 → 이 줄 전체가 값
            if let key = pendingKey {
                assign(key: key, value: line, to: &result)
                pendingKey = nil
                continue
            }

            // "키 : 값" 또는 "키: 값" 또는 전각 콜론
            if let (key, value) = splitKeyValue(line) {
                if value.isEmpty {
                    if matchedKey(key) != nil { pendingKey = key }
                } else {
                    assign(key: key, value: value, to: &result)
                }
                continue
            }

            // 콜론 없이 "PW 12345678" 처럼 공백으로 구분된 경우
            let tokens = line.split(separator: " ", maxSplits: 1).map(String.init)
            if tokens.count == 2, matchedKey(tokens[0]) != nil {
                assign(key: tokens[0], value: tokens[1], to: &result)
                continue
            }
        }

        // 키워드를 하나도 못 찾은 경우: 마지막 수단으로
        // 노이즈가 아닌 줄 중 처음 두 줄을 SSID / PW 후보로 추정
        if result.ssid.isEmpty && result.password.isEmpty {
            let candidates = lines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in
                    !line.isEmpty && line.count >= 4 &&
                    !noiseWords.contains(where: { line.lowercased().contains($0) })
                }
            if candidates.count >= 2 {
                result.ssid = candidates[0]
                result.password = candidates[1]
            }
        }

        return result
    }

    // MARK: - Helpers

    private static func splitKeyValue(_ line: String) -> (key: String, value: String)? {
        for separator in [":", "："] {
            if let range = line.range(of: separator) {
                let key = String(line[line.startIndex..<range.lowerBound])
                let value = String(line[range.upperBound...])
                return (
                    key.trimmingCharacters(in: .whitespaces),
                    value.trimmingCharacters(in: .whitespaces)
                )
            }
        }
        return nil
    }

    private enum KeyKind { case id, pw }

    private static func matchedKey(_ key: String) -> KeyKind? {
        let normalized = key.lowercased().replacingOccurrences(of: " ", with: "")
        // pw 키를 먼저 검사 ("p/w" 등), id 키의 "id"는 "ssid"에도 포함되므로 순서 중요
        if pwKeys.contains(where: { normalized == $0 || normalized.hasSuffix($0) }) { return .pw }
        if idKeys.contains(where: { normalized == $0 || normalized.hasSuffix($0) }) { return .id }
        return nil
    }

    private static func assign(key: String, value: String, to result: inout WifiCredentials) {
        switch matchedKey(key) {
        case .id: if result.ssid.isEmpty { result.ssid = value }
        case .pw: if result.password.isEmpty { result.password = value }
        case nil: break
        }
    }
}
