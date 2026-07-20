import Foundation
import NetworkExtension

/// NEHotspotConfiguration으로 실제 와이파이 연결을 수행
/// ⚠️ 요구사항:
///  - Signing & Capabilities에 "Hotspot Configuration" capability 추가
///  - 실제 기기에서만 동작 (시뮬레이터 불가)
enum WifiConnector {

    enum ConnectError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): return message
            }
        }
    }

    static func connect(ssid: String,
                        password: String,
                        completion: @escaping (Result<Void, Error>) -> Void) {
        let configuration: NEHotspotConfiguration
        if password.isEmpty {
            configuration = NEHotspotConfiguration(ssid: ssid)          // 개방형 네트워크
        } else {
            configuration = NEHotspotConfiguration(ssid: ssid,
                                                   passphrase: password,
                                                   isWEP: false)        // WPA/WPA2/WPA3
        }
        // false = 설정에 저장되어 다음부터 자동 재연결
        configuration.joinOnce = false

        NEHotspotConfigurationManager.shared.apply(configuration) { error in
            DispatchQueue.main.async {
                guard let nsError = error as NSError? else {
                    completion(.success(()))
                    return
                }
                // 이미 해당 네트워크에 연결된 상태는 성공으로 처리
                if nsError.domain == NEHotspotConfigurationErrorDomain,
                   nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                    completion(.success(()))
                    return
                }
                completion(.failure(ConnectError.failed(friendlyMessage(nsError))))
            }
        }
    }

    private static func friendlyMessage(_ error: NSError) -> String {
        guard error.domain == NEHotspotConfigurationErrorDomain,
              let code = NEHotspotConfigurationError(rawValue: error.code) else {
            return error.localizedDescription
        }
        switch code {
        case .invalidSSID: return "네트워크 이름(SSID)이 올바르지 않아요."
        case .invalidWPAPassphrase: return "비밀번호 형식이 올바르지 않아요. (WPA는 8자 이상)"
        case .userDenied: return "연결이 취소되었어요."
        case .pending: return "이전 연결 요청을 처리 중이에요. 잠시 후 다시 시도해 주세요."
        case .systemConfiguration: return "시스템 설정으로 관리되는 네트워크라 변경할 수 없어요."
        case .unknown: return "알 수 없는 오류가 발생했어요. 신호 범위 안에 있는지 확인해 주세요."
        case .joinOnceNotSupported: return "이 네트워크는 일회성 연결을 지원하지 않아요."
        case .alreadyAssociated: return "이미 연결되어 있어요."
        case .applicationIsNotInForeground: return "앱이 화면에 떠 있는 상태에서 시도해 주세요."
        case .invalidSSIDPrefix: return "SSID 접두사가 올바르지 않아요."
        default: return error.localizedDescription
        }
    }
}
