//
//  WifiSnapSpec.swift
//  WifiSnap
//
//  LeeoKit 계약(LeeoAppSpec) 준수 — 이 앱의 공통 기능 설정값 단일 소스.
//  피드백·리뷰·진단 구현은 전부 LeeoKit 에 있고, 앱은 이 설정만 제공한다.
//
//  ⚠️ recordType/구독 ID는 CloudKit Dashboard·기존 사용자 기기와의 계약이다 — 변경 금지.
//

import Foundation
import LeeoKit

enum WifiSnapSpec: LeeoAppSpec {
    static let appName = "마이파이"
    static let developerEmail = "leeo@kakao.com"
    /// 위젯과 나눠 쓰는 기록 — 백업 금고가 함께 떠 둔다.
    static let appGroups = ["group.com.leeo.wifisnap"]

    /// 공용 피드백 허브(FeedbackHub)로 수집 — appIdentifier(번들 ID)로 앱을 구분한다.
    /// 컨테이너 권한은 WifiSnap.entitlements 에 있다 — 빼면 CKContainer 를 만드는 순간 앱이 죽는다.
    static let feedback = LeeoFeedbackConfig(
        containerIdentifier: "iCloud.com.Ysoup.FeedbackHub",
        appIdentifier: "com.leeo.wifisnap"
    )

    /// 개인정보·지원 페이지 (LeeoKit 3.x 부터 필수). README.md 에 적힌 주소를 그대로 쓴다.
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/WifiSnap/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/WifiSnap/support.html")!,
        marketingURL: URL(string: "https://m1zz.github.io/WifiSnap/")!
    )

    /// App Store 앱 ID — 설정의 '리뷰 남기기'가 리뷰 작성 페이지로 바로 연결된다.
    static let appStoreID: String? = "6793472383"

    /// 수익모델 (LeeoKit 3.x 부터 필수) — 무료로 쓰다가, 가게 안내판은 Plus, 먼저 나타나는 것은 Pro.
    /// 칸마다 주 · 월 · 연 구독과 평생. 무엇이 어느 칸인지는 `ProFeature.tier` 한 곳에 있다 (→ Store/Plan.swift).
    static let monetization = LeeoMonetization.freemiumSubscription(
        LeeoSubscriptionConfig(
            productIDs: ProProduct.all,
            // 자체 약관이 없으므로 애플 표준 사용권 계약(EULA)을 건다. 구독을 파는 앱의 심사 필수 항목이다.
            termsURL: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
            entitlementIDs: Set(ProProduct.tierByProduct.keys),
            gate: LeeoGatePolicy(
                freeLimits: [Gate.savedNetworks: FreeLimit.savedNetworks, Gate.signs: FreeLimit.signs],
                proOnly: Set(ProFeature.allCases.map(\.rawValue))
                    .subtracting([ProFeature.unlimitedNetworks.rawValue, ProFeature.unlimitedSigns.rawValue])),
            // 개발자 응원 팁. ⚠️ 기능을 여는 상품이 아니다 — productIDs · entitlementIDs 에 넣지 않는다.
            tipJar: LeeoTipJarConfig(productIDs: ProProduct.tips)))

    /// 게이트 열쇠말 (무료 한도).
    enum Gate {
        static let savedNetworks = "savedNetworks"
        static let signs = "signs"
    }

    /// 익명 사용 통계 → FeedbackHub(CloudKit). 기본값(Noop)이면 부트스트랩이 아무것도 보내지 않는다.
    static let analytics: any LeeoAnalytics = LeeoUsageAnalytics(spec: WifiSnapSpec.self)
}

// MARK: - 팁 (개발자 응원하기)

extension WifiSnapSpec {
    /// 팁은 결제 리스너를 함께 쓰려고 LeeoStore 안에 둔다(→ PurchaseManager). 소모성 셋, 작은 것부터.
    @MainActor static var tipJar: LeeoTipJar { PurchaseManager.shared.store.tipJar! }
}

/// 팁을 부탁할 만한 순간 — 마이파이에 모아 둔 와이파이 수. 저장할 때마다 하나씩 는다.
enum WifiSnapTipMoments {
    /// 저장된 와이파이 수. 큰 것부터.
    static let saved = [30, 15, 5]

    /// 넘어선 순간, 인상적인 것부터.
    static func reached(savedCount count: Int) -> [LeeoTipMoment] {
        saved.filter { count >= $0 }.map { threshold in
            LeeoTipMoment(id: "saved.\(threshold)",
                          message: String(localized: "와이파이 \(count)개를 마이파이에 모아 두었어요",
                                          comment: "Tip ask card: how many Wi-Fi networks the person has saved"))
        }
    }
}
