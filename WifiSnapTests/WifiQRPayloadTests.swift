import XCTest


/// 와이파이 QR 문자열 — 만드는 쪽(QRCodeGenerator)과 읽는 쪽(WifiQRPayload)이 어긋나면
/// 공유한 QR로 상대 폰이 조용히 연결에 실패한다.
final class WifiQRPayloadTests: XCTestCase {

    func testParsesStandardWPAPayload() {
        let parsed = WifiQRPayload.parse("WIFI:S:Cafe_Momo;T:WPA;P:12345678;;")
        XCTAssertEqual(parsed, WifiCredentials(ssid: "Cafe_Momo", password: "12345678"))
    }

    func testParsesOpenNetworkWithoutPassword() {
        let parsed = WifiQRPayload.parse("WIFI:S:FreeWifi;T:nopass;;")
        XCTAssertEqual(parsed, WifiCredentials(ssid: "FreeWifi", password: ""))
    }

    func testFieldOrderAndCaseOfPrefixDoNotMatter() {
        let parsed = WifiQRPayload.parse("wifi:T:WPA;P:pass word!;S:Home 5G;;")
        XCTAssertEqual(parsed, WifiCredentials(ssid: "Home 5G", password: "pass word!"))
    }

    func testUnescapesSpecialCharacters() {
        let parsed = WifiQRPayload.parse(#"WIFI:S:My\;Net\:1;T:WPA;P:a\\b\,c\"d;;"#)
        XCTAssertEqual(parsed, WifiCredentials(ssid: "My;Net:1", password: #"a\b,c"d"#))
    }

    func testRejectsNonWifiPayloads() {
        XCTAssertNil(WifiQRPayload.parse("https://example.com"))
        XCTAssertNil(WifiQRPayload.parse("WIFI:"))
        XCTAssertNil(WifiQRPayload.parse("WIFI:T:WPA;P:12345678;;"))   // 이름 없음
    }

    /// 앱이 만든 QR을 앱이 다시 읽으면 원래 값이 그대로 나와야 한다 — 특수문자가 섞여도.
    func testGeneratorAndParserRoundTrip() {
        let samples: [(String, String)] = [
            ("Cafe_Momo", "12345678"),
            ("Leeo’s iPhone", "p;a:s,s\"w\\rd"),
            ("카페 모모 5G", "커피한잔1234"),
            ("Guest", "")
        ]
        for (ssid, password) in samples {
            let payload = QRCodeGenerator.wifiString(ssid: ssid, password: password)
            XCTAssertEqual(WifiQRPayload.parse(payload),
                           WifiCredentials(ssid: ssid, password: password),
                           "round trip failed for \(payload)")
        }
    }
}
