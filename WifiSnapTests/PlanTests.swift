import XCTest

/// 칸 · 상품 규칙. 상품 ID 는 App Store Connect 와의 계약이라 글자 하나만 바뀌어도 산 사람이 잠긴다.
final class PlanTests: XCTestCase {

    func testEarlyUserIsDecidedByFirstBuild() {
        XCTAssertTrue(EarlyUser.isBeforePaywall(originalAppVersion: "1"))
        XCTAssertTrue(EarlyUser.isBeforePaywall(originalAppVersion: "8"))
        XCTAssertFalse(EarlyUser.isBeforePaywall(originalAppVersion: "9"))
        XCTAssertFalse(EarlyUser.isBeforePaywall(originalAppVersion: "12"))
        XCTAssertFalse(EarlyUser.isBeforePaywall(originalAppVersion: ""))
    }

    func testHighestOwnedTierWins() {
        XCTAssertEqual(ProProduct.tier(owning: []), .free)
        XCTAssertEqual(ProProduct.tier(owning: [ProProduct.plusWeekly]), .plus)
        XCTAssertEqual(ProProduct.tier(owning: [ProProduct.plusLifetime, ProProduct.proMonthly]), .pro)
        XCTAssertEqual(ProProduct.tier(owning: [ProProduct.graduate]), .pro)
        XCTAssertEqual(ProProduct.tier(owning: [ProProduct.upgrade]), .pro)
        // 팁은 아무것도 열지 않는다
        XCTAssertEqual(ProProduct.tier(owning: Set(ProProduct.tips)), .free)
    }

    func testEverySoldProductOpensATier() {
        for id in ProProduct.all { XCTAssertNotNil(ProProduct.tierByProduct[id], id) }
        XCTAssertTrue(ProProduct.subscriptionIDs.isDisjoint(with: ProProduct.lifetimeIDs))
        XCTAssertEqual(ProProduct.subscriptionIDs.union(ProProduct.lifetimeIDs), Set(ProProduct.all))
    }

    func testPlusLifetimeOwnerBuysTheUpgrade() {
        XCTAssertEqual(ProProduct.id(.pro, .lifetime), ProProduct.proLifetime)
        XCTAssertEqual(ProProduct.id(.pro, .lifetime, ownsPlusLifetime: true), ProProduct.upgrade)
        XCTAssertEqual(ProProduct.id(.plus, .lifetime, ownsPlusLifetime: true), ProProduct.plusLifetime)
        XCTAssertEqual(ProProduct.id(.plus, .weekly), "com.leeo.wifisnap.plus.weekly")
    }

    func testProOpensEverything() {
        for feature in ProFeature.allCases { XCTAssertLessThanOrEqual(feature.tier, .pro) }
        XCTAssertEqual(ProFeature.widget.tier, .pro)
        XCTAssertEqual(ProFeature.a4Poster.tier, .plus)
    }
}
