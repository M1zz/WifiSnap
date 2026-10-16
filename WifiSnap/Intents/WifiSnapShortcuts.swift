import AppIntents

/// 와이파이 QR 보여주기 — 친구에게 비밀번호 대신 화면을 내미는, 이 앱의 가장 잦은 동작.
struct ShowWifiQRIntent: AppIntent {
    static var title: LocalizedStringResource = "와이파이 QR 보여주기"
    static var description = IntentDescription("지금 연결된 와이파이의 QR을 엽니다. 연결된 와이파이가 저장돼 있지 않으면 가장 최근에 저장한 와이파이를 엽니다.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .showWifiQR
        return .result()
    }
}

/// 와이파이 안내문 촬영 — 카페·숙소에서 안내문을 찍어 바로 연결.
struct ScanWifiPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "와이파이 안내문 촬영"
    static var description = IntentDescription("카메라를 열어 와이파이 안내문을 찍으면 이름과 비밀번호를 읽어 줍니다.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .scanWifiPhoto
        return .result()
    }
}

/// 설치만 하면 단축어 앱 · Spotlight · Siri 에 나타나는 앱 단축어.
struct WifiSnapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowWifiQRIntent(),
            phrases: [
                "\(.applicationName) 와이파이 QR 보여줘",
                "\(.applicationName)에서 와이파이 QR 열어줘",
                "\(.applicationName) QR"
            ],
            shortTitle: "와이파이 QR",
            systemImageName: "qrcode"
        )
        AppShortcut(
            intent: ScanWifiPhotoIntent(),
            phrases: [
                "\(.applicationName)로 와이파이 안내문 찍어줘",
                "\(.applicationName) 와이파이 촬영"
            ],
            shortTitle: "안내문 촬영",
            systemImageName: "camera.viewfinder"
        )
    }
}
