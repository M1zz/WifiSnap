import SwiftUI
import TipKit
import LeeoKit

@main
struct WifiSnapApp: App {
    init() {
        #if DEBUG
        // App Store 스크린샷 장면 — 저장소가 읽기 전에 예시 데이터를 심는다 (→ Shared/ScreenshotMode.swift)
        ScreenshotMode.seedIfNeeded()
        if ScreenshotMode.isActive { Tips.hideAllTipsForTesting() }
        #endif
        // LeeoKit 계약을 켜는 한 줄 (→ WifiSnapSpec.swift). 실행 횟수 기록 · 익명 사용 통계 ·
        // 크래시 진단 · DEBUG 프리플라이트. 통계·진단은 FeedbackHub(CloudKit)로 올라간다 —
        // 그 iCloud 컨테이너 권한은 WifiSnap.entitlements 에 있다.
        // flags: 원격 킬스위치(→ WifiSnapFlags.swift)도 함께 갱신한다 (백그라운드 · 6시간 쓰로틀).
        LeeoKit.bootstrap(WifiSnapSpec.self, flags: WifiSnapFlag.self)

        // TipKit 초기화 — 기능 안내 팁을 필요한 순간에 노출
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 실행 횟수·긍정 행동(연결·QR 저장)이 쌓이면 한 번 만족도를 묻는다.
                // 만족 → 시스템 리뷰 요청 / 아쉬움 → 피드백 화면
                .leeoSatisfactionCheck(WifiSnapSpec.self)
        }
    }
}
