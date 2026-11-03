import XCTest

/// 연결에 실패했을 때 권하는 '헷갈리는 글자' 후보. 확인 창이 시도마다 뜨므로 그럴듯한 몇 개만 내야 한다.
final class PasswordLookalikesTests: XCTestCase {

    func testLetterAmongDigitsBecomesDigit() {
        XCTAssertEqual(PasswordLookalikes.suggestions(for: "1234S678").first, "12345678")
        XCTAssertEqual(PasswordLookalikes.suggestions(for: "2O24cafe").first, "2024cafe")
    }

    func testDigitAmongLettersBecomesLetter() {
        XCTAssertEqual(PasswordLookalikes.suggestions(for: "passw0rd").first, "password")
    }

    func testCaseOfLookalikeLetterFollowsNeighbors() {
        XCTAssertEqual(PasswordLookalikes.suggestions(for: "helloWorld").contains("helloworld"), true)
    }

    func testCleanPasswordHasNoSuggestions() {
        XCTAssertEqual(PasswordLookalikes.suggestions(for: "abcd1234"), [])
        XCTAssertEqual(PasswordLookalikes.suggestions(for: ""), [])
    }

    func testLimit() {
        XCTAssertLessThanOrEqual(PasswordLookalikes.suggestions(for: "S5S5S5S5").count, 3)
    }

    func testRetryHidesTriedAndKeepsBase() {
        var retry = ConnectRetry()
        XCTAssertFalse(retry.hasFailed)
        retry.recordFailure(ssid: "KT_GIGA_5G", password: "1234S678", nameSuggestions: ["KT_GiGA_5G"])
        XCTAssertTrue(retry.hasFailed)
        XCTAssertEqual(retry.passwordSuggestions(current: "1234S678").first, "12345678")
        XCTAssertEqual(retry.nameSuggestions(current: "KT_GIGA_5G"), ["KT_GiGA_5G"])

        // 권해 준 후보로도 실패하면 그 후보는 빼고, 처음 읽은 값 기준의 나머지를 낸다
        retry.recordFailure(ssid: "KT_GiGA_5G", password: "12345678", nameSuggestions: [])
        XCTAssertFalse(retry.passwordSuggestions(current: "12345678").contains("12345678"))
        XCTAssertFalse(retry.passwordSuggestions(current: "12345678").contains("1234S678"))
        XCTAssertEqual(retry.nameSuggestions(current: "KT_GiGA_5G"), [])

        // 손으로 고치기 시작하면 비밀번호 후보를 거둔다
        XCTAssertEqual(retry.passwordSuggestions(current: "1234567"), [])
    }
}
