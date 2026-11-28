import SwiftUI
import CoreWLAN
import CoreLocation

/// 맥이 지금 붙어 있는 와이파이 이름.
///
/// macOS 도 와이파이 이름을 위치 정보로 보아, 위치 권한이 있어야 CoreWLAN 이 이름을 준다.
/// 비밀번호는 어떤 앱에도 주지 않는다 — 그래서 사용자가 한 번 넣어 두면 앱이 기억한다(→ NetworkStore).
@MainActor
final class MacWifiReader: NSObject, ObservableObject {
    @Published private(set) var ssid: String?
    /// 위치 권한이 없어 이름을 읽을 수 없다.
    @Published private(set) var needsPermission = false

    private let location = CLLocationManager()

    override init() {
        super.init()
        location.delegate = self
        refresh()
    }

    func refresh() {
        switch location.authorizationStatus {
        case .notDetermined, .denied, .restricted:
            needsPermission = true
        default:
            needsPermission = false
        }
        ssid = CWWiFiClient.shared().interface()?.ssid()
    }

    /// 처음이면 권한을 묻고, 이미 거절했으면 시스템 설정의 위치 서비스를 연다.
    func requestPermission() {
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension MacWifiReader: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }
}
