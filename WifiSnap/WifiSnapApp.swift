import SwiftUI
import TipKit
import LeeoKit

@main
struct WifiSnapApp: App {
    #if os(macOS)
    // 메뉴 막대 판과 큰 QR 창이 같은 목록을 본다
    @StateObject private var store = NetworkStore()
    @StateObject private var reader = MacWifiReader()
    #endif

    init() {
        // LeeoKit 계약을 켜는 한 줄 (→ WifiSnapSpec.swift). 백업 금고(예약된 복원 · 업데이트 직전 백업)가
        // 맨 먼저 돌아야 해서 저장소를 건드리는 어떤 일보다 앞에 둔다. 실행 횟수 기록 · 익명 사용 통계 ·
        // 크래시 진단 · DEBUG 프리플라이트. 통계·진단은 FeedbackHub(CloudKit)로 올라간다 —
        // 그 iCloud 컨테이너 권한은 WifiSnap.entitlements 에 있다.
        // flags: 원격 킬스위치(→ WifiSnapFlags.swift)도 함께 갱신한다 (백그라운드 · 6시간 쓰로틀).
        LeeoKit.bootstrap(WifiSnapSpec.self, flags: WifiSnapFlag.self)
        #if DEBUG && os(iOS)
        // App Store 스크린샷 장면 — 저장소가 읽기 전에 예시 데이터를 심는다 (→ Shared/ScreenshotMode.swift)
        ScreenshotMode.seedIfNeeded()
        if ScreenshotMode.isActive { Tips.hideAllTipsForTesting() }
        #endif

        // TipKit 초기화 — 기능 안내 팁을 필요한 순간에 노출
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    var body: some Scene {
        #if os(macOS)
        // 맥: 메뉴 막대에 사는 앱. 지금 와이파이 · 저장한 와이파이를 누르면 QR 창이 크게 뜬다 (→ WifiSnap/Mac).
        MenuBarExtra {
            MacMenuBarPanel()
                .environmentObject(store)
                .environmentObject(reader)
                .environment(\.locale, .app)
                .task { await PurchaseManager.shared.refresh() }
        } label: {
            Image(systemName: "qrcode")
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: MacQRWindow.id, for: UUID.self) { $networkID in
            MacQRWindow(networkID: networkID)
                .environmentObject(store)
                .environment(\.locale, .app)
        }
        .defaultSize(width: 520, height: 680)
        #else
        WindowGroup {
            ContentView()
                // 실행 횟수·긍정 행동(연결·QR 저장)이 쌓이면 한 번 만족도를 묻는다.
                // 만족 → 시스템 리뷰 요청 / 아쉬움 → 피드백 화면
                .leeoSatisfactionCheck(WifiSnapSpec.self)
                // 개발자가 보낸 의견에 답장하면, 앱이 앞으로 올 때 답장을 시트로 보여 준다 (LeeoKit).
                .leeoFeedbackReplyNotice(WifiSnapSpec.self)
                // 아이폰 듀오: 창 크기로 접힘을 재서 아래로 흘린다. 시트 · 알림창도 접힌 선을 비킨다 (LeeoKit Fold).
                .foldAware()
                // 유료가 되면 콘페티, 모든 사용자가 한 번은 감사를 받는다. 판정은 LeeoStore 가 한다 (LeeoKit).
                .leeoCelebrations(appName: WifiSnapSpec.appName)
                // 영수증을 읽고 요금제 상품을 불러온다. 팁 상품 · 끝나지 않은 팁도 LeeoStore 가 함께 챙긴다.
                .task { await PurchaseManager.shared.refresh() }
                // 숫자는 0-9 로 (아랍어에서 ١٢٣ 과 섞이지 않게 → Locale.app)
                .environment(\.locale, .app)
        }
        #endif
    }
}

// MARK: - 숫자는 0-9 로

extension Locale {
    /// 화면에 쓰는 로케일. 아랍어에서는 숫자를 0-9 로 맞춘다 — 사우디 기기는 ١٢٣ 이 기본이라
    /// "لوحاتي (١٢)" 와 문구 속 "8 أحرف" 가 한 화면에 섞였다. 다른 언어는 기기 그대로.
    static let app: Locale = {
        let current = Locale.current
        guard Bundle.main.preferredLocalizations.first == "ar" else { return current }
        var parts = Locale.Components(locale: current)
        parts.numberingSystem = Locale.NumberingSystem("latn")
        return Locale(components: parts)
    }()
}
