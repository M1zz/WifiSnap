import SwiftUI
import TipKit
import LeeoKit

@main
struct WifiSnapApp: App {
    init() {
        // LeeoKit 계약을 켜는 한 줄 (→ WifiSnapSpec.swift). 실행 횟수 기록 · 익명 사용 통계 ·
        // 크래시 진단 · DEBUG 프리플라이트. 통계·진단은 FeedbackHub(CloudKit)로 올라간다 —
        // 그 iCloud 컨테이너 권한은 WifiSnap.entitlements 에 있다.
        LeeoKit.bootstrap(WifiSnapSpec.self)

        // TipKit 초기화 — 기능 안내 팁을 필요한 순간에 노출
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
