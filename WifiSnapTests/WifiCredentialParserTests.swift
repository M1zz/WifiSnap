import XCTest


/// 안내문 사진에서 읽은 줄 → 아이디·비밀번호. 매장마다 표기가 제각각이라 회귀가 잦은 곳이다.
final class WifiCredentialParserTests: XCTestCase {

    private func parse(_ lines: [String]) -> WifiCredentials {
        WifiCredentialParser.parse(lines: lines).credentials
    }

    func testLabelsOnSeparateLines() {
        XCTAssertEqual(parse(["ID : CAFE_MOMO", "PW : momo1234"]),
                       WifiCredentials(ssid: "CAFE_MOMO", password: "momo1234"))
    }

    func testKoreanLabels() {
        XCTAssertEqual(parse(["아이디 MomoGuest", "비밀번호 coffee2024"]),
                       WifiCredentials(ssid: "MomoGuest", password: "coffee2024"))
    }

    func testValueOnFollowingLine() {
        XCTAssertEqual(parse(["SSID", "Home_5G", "PW :", "a1b2c3d4"]),
                       WifiCredentials(ssid: "Home_5G", password: "a1b2c3d4"))
    }

    func testBothOnOneLine() {
        XCTAssertEqual(parse(["ID: cafe  PW: 12345678"]),
                       WifiCredentials(ssid: "cafe", password: "12345678"))
    }

    func testCombinedLabel() {
        XCTAssertEqual(parse(["ID/PW : cafe / 12345678"]),
                       WifiCredentials(ssid: "cafe", password: "12345678"))
    }

    func testCandidatesAndTokensKeepWhatWasRead() {
        let result = WifiCredentialParser.parse(lines: ["ID : CAFE_MOMO", "PW : momo1234"])
        XCTAssertEqual(result.ssidCandidates.first, "CAFE_MOMO")
        XCTAssertTrue(result.tokens.contains("CAFE_MOMO"))
        XCTAssertTrue(result.tokens.contains("momo1234"))
    }

    func testNothingRecognizableYieldsEmptyCredentials() {
        XCTAssertEqual(parse([]), WifiCredentials())
    }
}
