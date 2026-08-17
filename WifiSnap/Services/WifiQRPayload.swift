import Foundation

/// 와이파이 QR(`WIFI:S:이름;T:WPA;P:비밀번호;;`)의 내용을 자격증명으로 되돌린다.
///
/// 안내판에는 QR이 함께 인쇄된 경우가 많은데, 그 안에는 OCR이 글자 모양으로 추측할 필요가 없는
/// 정확한 이름과 비밀번호가 들어 있다. 사진에서 QR을 찾았다면 글자를 읽는 것보다 항상 낫다.
enum WifiQRPayload {

    static func parse(_ payload: String) -> WifiCredentials? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 5, trimmed.prefix(5).uppercased() == "WIFI:" else { return nil }

        var fields: [Character: String] = [:]
        var key: Character?
        var value = ""
        var escaped = false

        /// 모아 둔 한 필드를 확정한다. 같은 키가 두 번 나오면 앞의 것을 남긴다.
        func flush() {
            if let key, !value.isEmpty, fields[key] == nil { fields[key] = value }
            key = nil
            value = ""
        }

        // 필드는 ';'로 나뉘고 키와 값은 ':'로 갈리는데, 값 안의 ';' ':' '\'는 백슬래시로
        // 이스케이프돼 있다. 그래서 통째로 쪼개지 않고 한 글자씩 훑는다.
        for character in trimmed.dropFirst(5) {
            if escaped {
                value.append(character)
                escaped = false
                continue
            }
            switch character {
            case "\\":
                escaped = true
            case ";":
                flush()
            case ":" where key == nil && value.count == 1:
                key = value.first
                value = ""
            default:
                value.append(character)
            }
        }
        flush()

        guard let ssid = fields["S"] ?? fields["s"], !ssid.isEmpty else { return nil }
        return WifiCredentials(ssid: ssid, password: fields["P"] ?? fields["p"] ?? "")
    }
}
