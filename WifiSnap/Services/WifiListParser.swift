import Foundation

/// iOS '설정 > Wi-Fi' 화면 캡처에서 와이파이 이름만 골라내는 파서.
///
/// iOS는 기기가 아는 와이파이 목록을 앱에 주지 않으므로, 사용자가 그 화면을 캡처해 주면
/// 여기서 이름을 읽어 선택 목록으로 쓴다. 잘못 걸러낸 것은 사용자가 화면에서 고치도록 하고,
/// 이 파서는 "확실한 잡음만 버리고 나머지는 후보로 남기는" 쪽으로 느슨하게 동작한다.
enum WifiListParser {

    /// 화면 캡처의 인식 결과에서 와이파이 이름 후보를 위에서 아래 순서로 뽑는다
    static func ssids(from lines: [RecognizedLine]) -> [String] {
        var seen = Set<String>()
        return lines.compactMap { line -> String? in
            // 이름은 항상 왼쪽 정렬. 오른쪽의 '연결됨' 같은 상태 텍스트는 버린다.
            guard line.boundingBox.minX < 0.5 else { return nil }

            let text = clean(line.text)
            guard isCandidate(text), seen.insert(text.lowercased()).inserted else { return nil }
            return text
        }
    }

    // MARK: - Private

    /// 행 끝에 붙는 말줄임표·구분 기호를 걷어낸다 ("기타…", "네트워크 선택…")
    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n…·>‹›"))
    }

    /// 화면 자체의 UI 문구 — 줄 전체가 이것과 같을 때만 버린다.
    /// (부분 일치로 버리면 "KT_WiFi" 같은 진짜 이름까지 사라진다)
    private static let chrome: Set<String> = [
        // 화면·섹션 제목
        "wi-fi", "wifi", "와이파이", "설정", "settings", "편집", "edit", "정보", "info",
        "내 네트워크", "my networks", "네트워크", "networks", "네트워크 선택", "choose a network",
        "기타 네트워크", "other networks", "공용 네트워크", "public networks", "기타", "other",
        // 토글·옵션 행
        "네트워크 연결 요청", "ask to join networks", "자동 연결", "auto-join",
        "인터넷 공유 연결 요청", "auto-join hotspot", "알림", "notify",
        "이 네트워크 지우기", "forget this network",
        // 상태 표시
        "연결됨", "connected", "연결 안 됨", "not connected", "연결 중", "connecting",
        "보안 수준이 낮은 보안", "보안 수준이 낮음", "weak security",
        "안전하지 않은 네트워크", "unsecured network", "개인 정보 보호 경고", "privacy warning"
    ]

    /// 이름 후보로 볼지 판단
    private static func isCandidate(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard !chrome.contains(text.lowercased()) else { return false }
        // 설명 문구(푸터)는 문장 형태로 길다
        guard text.count <= 32, !isSentence(text) else { return false }
        // 상태바 시각("9:41", "오전 11:53")
        guard !isClock(text) else { return false }
        // SSID 규격(1~32바이트)과 상식에 맞는지
        return SSIDMatcher.isPlausible(text)
    }

    private static let sentenceEndings = ["습니다", "됩니다", "하세요", "합니다", "십시오", "세요."]

    private static func isSentence(_ text: String) -> Bool {
        sentenceEndings.contains { text.contains($0) }
    }

    private static func isClock(_ text: String) -> Bool {
        if text.hasPrefix("오전") || text.hasPrefix("오후") || text.hasPrefix("AM") || text.hasPrefix("PM") {
            return true
        }
        // "9:41" 처럼 숫자와 콜론만으로 이루어진 줄
        let clockCharacters = CharacterSet(charactersIn: "0123456789:")
        return text.contains(":") && text.rangeOfCharacter(from: clockCharacters.inverted) == nil
    }
}
