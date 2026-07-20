import Foundation
import CoreLocation
import NetworkExtension

/// 현재 연결된 와이파이의 SSID를 감지
/// ⚠️ 요구사항:
///  - Signing & Capabilities에 "Access Wi-Fi Information" capability 추가
///  - Info.plist에 위치 권한 문구(NSLocationWhenInUseUsageDescription) 추가
///    (iOS 정책상 SSID 조회에는 위치 권한이 필요 — SSID로 위치를 추정할 수 있기 때문)
/// 참고: iOS는 보안상 '비밀번호'는 어떤 앱에도 제공하지 않으므로,
///       비밀번호는 사용자가 최초 1회 입력해야 하며 이후에는 앱이 저장해 재사용합니다.
@MainActor
final class CurrentNetworkService: NSObject, ObservableObject {

    @Published var currentSSID: String?
    @Published var permissionDenied = false

    private let locationManager = CLLocationManager()
    private var fetchAfterAuthorization = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    /// 권한 상태를 확인하고 SSID를 가져옴 (필요 시 위치 권한 요청)
    func refresh() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            fetchAfterAuthorization = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            permissionDenied = false
            fetchSSID()
        case .denied, .restricted:
            permissionDenied = true
            currentSSID = nil
        @unknown default:
            currentSSID = nil
        }
    }

    private func fetchSSID() {
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            Task { @MainActor in
                self?.currentSSID = network?.ssid
            }
        }
    }
}

extension CurrentNetworkService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.fetchAfterAuthorization else { return }
            self.fetchAfterAuthorization = false
            self.refresh()
        }
    }
}
