import SwiftUI
import TipKit

@main
struct WifiSnapApp: App {
    init() {
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
