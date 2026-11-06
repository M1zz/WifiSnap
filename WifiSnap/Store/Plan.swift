//
//  Plan.swift
//  WifiSnap
//
//  마이파이의 세 칸(무료 · Plus · Pro)과 칸마다 여는 것. **무엇이 잠기는지는 이 파일 한 곳에만 적는다.**
//  페이월의 비교표 · 잠긴 자리 · 설정의 '내 버전'이 모두 여기서 읽는다.
//
//  선은 한 문장으로 긋는다 — "찍어서 연결하고 QR로 나누는 일은 무료, 가게 안내판은 Plus, 먼저 나타나는 것은 Pro".
//   · 무료: 찍어서 연결, 글자 조각 끌어다 고치기, 지금 와이파이 · 핫스팟 QR, 와이파이 20개, 안내판 1장(카드 · 테마 2개),
//           이미지 저장 · 공유 · 인쇄
//   · Plus: 와이파이 무제한, 안내판 무제한 · 복제, 테마 7개, 가게 이름 · 덧붙일 문구 · 라벨, A4 포스터
//   · Pro:  Plus 전부 + 홈 · 잠금 화면 위젯, 연결했던 곳 지도, 단축어 · Siri, 캡처로 목록 가져오기
//
//  ⚠️ 이미 저장한 와이파이 · 안내판은 한도와 관계없이 보고 고치고 인쇄하고 지울 수 있다.
//     잠그는 것은 **새로 더하는 것**과 **잠긴 것을 새로 고르는 것**뿐이다.
//

import Foundation
import StoreKit

/// 칸. 값이 클수록 더 많이 연다. Pro 는 Plus 를 전부 포함한다.
enum ProTier: Int, Comparable, CaseIterable {
    case free = 0
    case plus = 1
    case pro = 2

    static func < (lhs: ProTier, rhs: ProTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .free: String(localized: "무료")
        case .plus: String(localized: "마이파이 Plus")
        case .pro:  String(localized: "마이파이 Pro")
        }
    }
}

/// 값을 받고 여는 것들.
enum ProFeature: String, CaseIterable, Identifiable {
    case unlimitedNetworks
    case unlimitedSigns
    case allThemes
    case signText
    case a4Poster
    case widget
    case map
    case shortcuts
    case captureImport

    var id: String { rawValue }

    /// 이 기능을 여는 가장 낮은 칸.
    var tier: ProTier {
        switch self {
        case .unlimitedNetworks, .unlimitedSigns, .allThemes, .signText, .a4Poster: .plus
        case .widget, .map, .shortcuts, .captureImport:                             .pro
        }
    }
}

/// 무료 칸의 한도.
enum FreeLimit {
    /// 저장한 와이파이. 21번째를 저장하려 할 때 페이월이 뜬다.
    static let savedNetworks = 20
    /// 손님 안내판. 두 번째를 만들거나 복제하려 할 때 페이월이 뜬다.
    static let signs = 1
    /// 무료로 고를 수 있는 안내판 테마 — 기본(미드나잇)과 흑백 인쇄용(모노).
    static let themeIDs: Set<String> = ["midnight", "mono"]
}

// MARK: - 상품

/// App Store Connect · `WifiSnap.storekit` 과 **글자 하나까지 같아야 한다.**
///
/// 주 · 월 · 연 구독 여섯은 구독 그룹 하나에 넣는다(Pro 가 위 단계). 그래야 Plus 에서 Pro 로 갈아탈 수 있다.
/// ⚠️ 언제나 평생 패스는 팔지 않는다(포트폴리오 전체에서 판매를 멈췄다).
enum ProProduct {
    private static let prefix = "com.leeo.wifisnap"

    static let plusWeekly   = prefix + ".plus.weekly"
    static let plusMonthly  = prefix + ".plus.monthly"
    static let plusYearly   = prefix + ".plus.yearly"
    static let plusLifetime = prefix + ".plus"
    static let proWeekly    = prefix + ".pro.weekly"
    static let proMonthly   = prefix + ".pro.monthly"
    static let proYearly    = prefix + ".pro.yearly"
    static let proLifetime  = prefix + ".pro"
    /// Plus 평생을 산 사람이 Pro 평생으로 올리는 값.
    static let upgrade      = prefix + ".pro.upgrade"
    /// 구독 중인 사람의 졸업가 Pro 평생 (→ LeeoGraduation).
    static let graduate     = prefix + ".pro.graduate"

    /// 개발자 응원 팁. 아무것도 열지 않는다 — `all` · `tierByProduct` 에 넣지 않는다.
    static let tips = [prefix + ".tip.small", prefix + ".tip.medium", prefix + ".tip.large"]

    /// 상품마다 여는 칸. 구독은 같은 칸의 평생과 같은 권한, 올리기 · 졸업은 Pro 평생이다.
    static let tierByProduct: [String: ProTier] = [
        plusWeekly: .plus, plusMonthly: .plus, plusYearly: .plus, plusLifetime: .plus,
        proWeekly: .pro, proMonthly: .pro, proYearly: .pro, proLifetime: .pro,
        upgrade: .pro, graduate: .pro,
    ]

    /// 페이월이 불러오는 상품.
    static let all = [plusYearly, plusLifetime, plusMonthly, plusWeekly,
                      proYearly, proLifetime, proMonthly, proWeekly,
                      upgrade, graduate]

    static let lifetimeIDs: Set<String> = [plusLifetime, proLifetime, upgrade, graduate]
    static let subscriptionIDs: Set<String> = [plusWeekly, plusMonthly, plusYearly,
                                               proWeekly, proMonthly, proYearly]

    /// 가진 상품들이 여는 칸. 가장 높은 것을 쓴다.
    static func tier(owning ids: Set<String>) -> ProTier {
        ids.compactMap { tierByProduct[$0] }.max() ?? .free
    }

    /// 칸마다 고르는 길 — 연이 기본, 평생, 그리고 펼쳐 보이는 월 · 주.
    enum Term: CaseIterable {
        case yearly, lifetime, monthly, weekly
    }

    /// 그 칸 · 그 길의 상품 ID. Plus 평생을 가진 사람의 Pro 평생은 올리기 상품이다.
    static func id(_ tier: ProTier, _ term: Term, ownsPlusLifetime: Bool = false) -> String {
        switch (tier, term) {
        case (.pro, .yearly):   proYearly
        case (.pro, .lifetime): ownsPlusLifetime ? upgrade : proLifetime
        case (.pro, .monthly):  proMonthly
        case (.pro, .weekly):   proWeekly
        case (_, .yearly):      plusYearly
        case (_, .lifetime):    plusLifetime
        case (_, .monthly):     plusMonthly
        case (_, .weekly):      plusWeekly
        }
    }
}

// MARK: - 페이월 전부터 쓰던 사람

/// 페이월이 없던 빌드를 받은 사람은 무료로 쓰던 것을 잃지 않게 Pro 평생으로 연다.
/// 위젯 · 안내판 여러 장을 이미 쓰고 있을 수 있다.
enum EarlyUser {
    /// 페이월이 없던 마지막 빌드(1.0.4 빌드 8).
    /// ⚠️ 한 번 나가면 바꾸지 않는다. 올리면 그 사이에 받은 사람에게 공짜 Pro 가 생기고, 내리면 쓰던 사람이 잠긴다.
    static let lastBuildBeforePaywall = 8

    /// App Store 가 서명한 최초 다운로드 빌드로 알아본다. 지웠다 다시 받아도 같다.
    /// 시험 환경(Xcode · 샌드박스 · TestFlight)은 최초 빌드가 엉뚱하게 오므로 출시 영수증만 믿는다.
    static func installedBeforePaywall() async -> Bool {
        guard case .verified(let app)? = try? await AppTransaction.shared,
              app.environment == .production else { return false }
        return isBeforePaywall(originalAppVersion: app.originalAppVersion)
    }

    /// iOS 의 `originalAppVersion` 은 처음 받은 빌드의 CFBundleVersion(빌드 번호)이다.
    static func isBeforePaywall(originalAppVersion: String) -> Bool {
        guard let build = Int(originalAppVersion.split(separator: ".").first ?? "") else { return false }
        return build <= lastBuildBeforePaywall
    }
}
