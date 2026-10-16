import XCTest


/// OCR · 붙여넣기로 들어온 이름을 바로잡는 규칙. 한 바이트만 달라도 연결이 실패한다.
final class SSIDMatcherTests: XCTestCase {

    func testSanitizeRemovesInvisibleCharacters() {
        XCTAssertEqual(SSIDMatcher.sanitize("\u{200B}Cafe\u{FEFF}Momo\u{200D} "), "CafeMomo")
    }

    func testSanitizeFoldsFullwidthAndSmartQuotesOnlyWhenAsked() {
        XCTAssertEqual(SSIDMatcher.sanitize("ＳＫ＿ＷｉＦｉ"), "SK_WiFi")
        XCTAssertEqual(SSIDMatcher.sanitize("Leeo’s iPhone"), "Leeo's iPhone")
        // 직접 친 이름은 그 자체가 정답 — 스마트 어포스트로피를 그대로 둔다
        XCTAssertEqual(SSIDMatcher.sanitize("Leeo’s iPhone", foldLookalikes: false), "Leeo’s iPhone")
    }

    func testSanitizeLeavesHangulAlone() {
        XCTAssertEqual(SSIDMatcher.sanitize("카페모모_5G"), "카페모모_5G")
    }

    func testCaseVariantsPutBrandSpellingFirstAndExcludeOriginal() {
        let variants = SSIDMatcher.caseVariants(of: "iptime_wifi")
        XCTAssertEqual(variants.first, "ipTIME_WiFi")
        XCTAssertFalse(variants.contains("iptime_wifi"))
        XCTAssertTrue(variants.contains("IPTIME_WIFI"))
    }

    func testCaseVariantsEmptyForNamesWithoutLetters() {
        XCTAssertEqual(SSIDMatcher.caseVariants(of: "1234-5678"), [])
    }

    func testBrandCanonicalOnlyTouchesWholeShortTokens() {
        XCTAssertEqual(SSIDMatcher.brandCanonical("kt_giga_5g"), "KT_GIGA_5g")
        // pocket 안의 'kt'는 브랜드가 아니다
        XCTAssertEqual(SSIDMatcher.brandCanonical("pocket"), "pocket")
    }

    func testIsPlausible() {
        XCTAssertTrue(SSIDMatcher.isPlausible("Cafe_Momo"))
        XCTAssertFalse(SSIDMatcher.isPlausible(""))
        XCTAssertFalse(SSIDMatcher.isPlausible("----"))
        XCTAssertFalse(SSIDMatcher.isPlausible(String(repeating: "a", count: 33)))   // 32바이트 초과
    }

    func testBestMatchCorrectsTypicalOCRConfusions() {
        let known = ["CAFE_MOMO_5G", "Home"]
        XCTAssertEqual(SSIDMatcher.bestMatch(for: "CAFE_M0M0_5G", in: known), "CAFE_MOMO_5G")
        XCTAssertEqual(SSIDMatcher.bestMatch(for: "cafe momo 5g", in: known), "CAFE_MOMO_5G")
    }

    func testBestMatchRefusesShortOrDistantNames() {
        // 짧은 이름은 한 글자 차이로도 오교정 위험이 크다
        XCTAssertNil(SSIDMatcher.bestMatch(for: "Hame", in: ["Home"]))
        XCTAssertNil(SSIDMatcher.bestMatch(for: "Starbucks", in: ["CAFE_MOMO_5G"]))
    }
}
