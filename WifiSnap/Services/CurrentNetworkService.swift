import Foundation
import CoreLocation
import NetworkExtension
import WidgetKit

/// 현재 연결된 와이파이의 SSID와 사용자의 현재 위치를 감지
/// ⚠️ 요구사항:
///  - Signing & Capabilities에 "Access Wi-Fi Information" capability 추가
///  - Info.plist에 위치 권한 문구(NSLocationWhenInUseUsageDescription) 추가
///    (iOS 정책상 SSID 조회에는 위치 권한이 필요 — SSID로 위치를 추정할 수 있기 때문)
/// 참고: iOS는 보안상 '비밀번호'는 어떤 앱에도 제공하지 않으므로,
///       비밀번호는 사용자가 최초 1회 입력해야 하며 이후에는 앱이 저장해 재사용합니다.
@MainActor
final class CurrentNetworkService: NSObject, ObservableObject {

    @Published var currentSSID: String? {
        didSet {
            guard oldValue != currentSSID else { return }
            publishCurrentSSIDForWidget()
        }
    }
    @Published var permissionDenied = false
    /// 근처 와이파이 추천에 쓰는 현재 위치
    @Published var currentLocation: CLLocation?
    /// SSID 조회를 한 번이라도 끝냈는지 (연결 여부가 확정됐다는 신호).
    /// 이 값이 true인데 currentSSID가 nil이면 '연결된 와이파이 없음'이 확정된 상태.
    @Published var ssidResolved = false
    /// 이 앱이 설정해 둔 SSID들 — iOS가 알려주는 '실제로 존재했던' 이름이라 선택 후보로 신뢰할 수 있다.
    /// (주변 와이파이 스캔은 iOS가 앱에 허용하지 않으므로 이게 목록을 넓힐 수 있는 유일한 수단)
    @Published var configuredSSIDs: [String] = []
    /// 위치 권한이 있어 SSID를 읽을 수 있는 상태인지 — 연결 후 검증 가능 여부와 직결
    @Published var canReadSSID = false

    private let locationManager = CLLocationManager()
    private var fetchAfterAuthorization = false

    override init() {
        super.init()
        locationManager.delegate = self
        // 근처 추천 용도라 정밀도는 낮춰 배터리 절약
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 30
    }

    /// 권한 상태를 확인하고 SSID·위치를 가져옴 (필요 시 위치 권한 요청)
    func refresh() {
        // 설정해 둔 SSID 조회는 위치 권한과 무관하므로 항상 갱신
        loadConfiguredSSIDs()

        switch locationManager.authorizationStatus {
        case .notDetermined:
            fetchAfterAuthorization = true
            canReadSSID = false
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            permissionDenied = false
            canReadSSID = true
            locationManager.startUpdatingLocation()
            fetchSSID()
        case .denied, .restricted:
            permissionDenied = true
            canReadSSID = false
            currentSSID = nil
            ssidResolved = true   // 권한이 없어 조회 불가 = '연결 없음'으로 확정
        @unknown default:
            canReadSSID = false
            currentSSID = nil
            ssidResolved = true
        }
    }

    /// 지금 연결된 SSID를 공유 저장소에 남겨 위젯이 읽게 한다.
    ///
    /// 위젯 익스텐션은 NEHotspotNetwork.fetchCurrent를 쓸 수 없다(포그라운드 앱만 허용).
    /// 그래서 위젯의 '지금 연결된 와이파이'는 **앱이 마지막으로 확인한 시점**의 값이다 —
    /// 앱을 열지 않고 와이파이를 바꾸면 위젯은 그 사실을 알 수 없다.
    private func publishCurrentSSIDForWidget() {
        let store = SharedDefaults.store
        if let ssid = currentSSID, !ssid.isEmpty {
            store.set(ssid, forKey: SharedDefaults.currentSSIDKey)
        } else {
            store.removeObject(forKey: SharedDefaults.currentSSIDKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 이 앱이 넣어둔 와이파이 설정 목록 (iOS 11+). 시뮬레이터에서는 항상 빈 배열.
    private func loadConfiguredSSIDs() {
        NEHotspotConfigurationManager.shared.getConfiguredSSIDs { [weak self] ssids in
            Task { @MainActor in
                self?.configuredSSIDs = ssids
            }
        }
    }

    private func fetchSSID() {
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            Task { @MainActor in
                self?.currentSSID = network?.ssid
                self?.ssidResolved = true
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

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 일시적 실패는 무시 — 다음 업데이트에서 회복됨
    }
}
