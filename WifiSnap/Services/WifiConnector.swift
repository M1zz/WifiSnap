import Foundation
import Network
import NetworkExtension

/// NEHotspotConfiguration으로 실제 와이파이 연결을 수행
/// ⚠️ 요구사항:
///  - Signing & Capabilities에 "Hotspot Configuration" capability 추가
///  - 실제 기기에서만 동작 (시뮬레이터 불가)
///
/// 이 파일의 어려움은 전부 한 가지에서 나온다: **apply()의 성공은 '연결됐다'는 뜻이 아니다.**
/// 존재하지 않는 이름도, 비밀번호가 틀린 네트워크도 apply()는 에러 없이 통과한다.
/// 그래서 apply 뒤에 실제로 붙었는지 따로 확인해야 하고, 확인이 애매할 때
/// 섣불리 실패로 처리하면 **멀쩡히 붙은 연결을 앱이 도로 끊어버린다**.
enum WifiConnector {

    /// 연결 시도가 끝난 상태
    struct Success {
        /// 실제로 붙은 이름. iOS가 알려준 표기가 있으면 그것을 쓴다(대소문자 교정 효과).
        let ssid: String
        /// 그 이름에 붙은 것까지 확인했는지. false = 설정은 넣었지만 확인할 방법이 없었음.
        let verified: Bool
    }

    enum ConnectError: LocalizedError {
        case emptySSID
        case ssidTooLong
        /// WPA는 8~63자, WEP은 5·13자만 가능하다. 어디에도 안 맞는 길이.
        case badPasswordLength(Int)
        /// 그 이름의 와이파이에 끝내 붙지 못함. suggestions는 대소문자만 다른 대안.
        case notFound(ssid: String, suggestions: [String])
        case message(String)

        var errorDescription: String? {
            switch self {
            case .emptySSID:
                return "와이파이 이름이 비어 있어요."
            case .ssidTooLong:
                return "와이파이 이름이 너무 길어요. (최대 32바이트)"
            case .badPasswordLength(let count):
                return "비밀번호가 \(count)자예요. 와이파이 비밀번호는 8자 이상이어야 해요(구형 WEP은 5자 또는 13자). 빠뜨린 글자가 없는지 확인해 주세요."
            case .notFound(let ssid, let suggestions):
                var text = "'\(ssid)' 와이파이에 붙지 못했어요.\n"
                text += "이름·비밀번호의 대소문자까지 정확한지, 신호 범위 안에 있는지 확인해 주세요."
                if !suggestions.isEmpty {
                    text += "\n\n이런 표기일 수도 있어요:\n" + suggestions.map { "• \($0)" }.joined(separator: "\n")
                }
                return text
            case .message(let text):
                return text
            }
        }
    }

    // 한 번의 시도에서 '붙었는지' 지켜보는 시간과 간격
    private static let verifyWindow: TimeInterval = 10
    private static let pollInterval: TimeInterval = 0.7

    // MARK: - Public

    /// - Parameters:
    ///   - canReadSSID: 위치 권한이 있어 현재 SSID를 읽을 수 있는지.
    ///     false면 '붙었는지'를 이름으로 확인할 수 없어 와이파이 경로 유무로만 판단한다.
    ///   - onProgress: 재시도처럼 시간이 걸리는 단계를 사용자에게 알리기 위한 콜백.
    static func connect(ssid rawSSID: String,
                        password rawPassword: String,
                        canReadSSID: Bool,
                        onProgress: @escaping (String) -> Void = { _ in },
                        completion: @escaping (Result<Success, Error>) -> Void) {
        let ssid = SSIDMatcher.sanitize(rawSSID)
        // 비밀번호는 대소문자·기호가 전부 의미를 가지므로 '보이지 않는 문자'만 걷어내고 그대로 쓴다
        let password = SSIDMatcher.sanitize(rawPassword)

        guard !ssid.isEmpty else { return completion(.failure(ConnectError.emptySSID)) }
        guard ssid.utf8.count <= 32 else { return completion(.failure(ConnectError.ssidTooLong)) }

        guard let security = Security.forPassword(password) else {
            return completion(.failure(ConnectError.badPasswordLength(password.count)))
        }

        // 이미 그 네트워크에 있으면 시스템 확인 창을 띄울 이유가 없다.
        // (대소문자만 다른 경우도 여기서 잡혀 iOS 표기로 교정된다)
        currentSSID(canReadSSID: canReadSSID) { current in
            if let current, current.caseInsensitiveCompare(ssid) == .orderedSame {
                completion(.success(Success(ssid: current, verified: true)))
                return
            }
            // 1차는 사용자가 준 이름 그대로. 못 붙으면 대소문자 표기만 바꿔 한 번 더 —
            // OCR이 가장 자주 틀리는 게 대소문자인데 SSID는 그걸 구분하기 때문이다.
            // (시도마다 시스템 확인 창이 뜨므로 재시도는 가장 유력한 후보 하나로 제한한다)
            let fallback = SSIDMatcher.caseVariants(of: ssid).first
            attempt(ssid: ssid, password: password, security: security, canReadSSID: canReadSSID) { result in
                guard isNotFound(result), let fallback else {
                    return completion(result)
                }
                onProgress("'\(fallback)' 표기로 다시 시도 중…")
                attempt(ssid: fallback, password: password, security: security,
                        canReadSSID: canReadSSID) { retry in
                    guard isNotFound(retry) else { return completion(retry) }
                    // 재시도도 실패 — 안내는 사용자가 처음 준 이름 기준으로, 남은 후보와 함께
                    let others = SSIDMatcher.caseVariants(of: ssid).filter { $0 != fallback }
                    completion(.failure(ConnectError.notFound(ssid: ssid, suggestions: others)))
                }
            }
        }
    }

    // MARK: - 한 번의 시도

    /// 비밀번호 길이로 결정되는 보안 방식. WPA와 WEP은 허용 길이가 겹치지 않는다.
    private enum Security {
        case open
        case wpa
        case wep

        static func forPassword(_ password: String) -> Security? {
            switch password.count {
            case 0: return .open
            case 5, 13: return .wep          // WPA가 받지 않는 길이 = 구형 WEP 키
            case 8...63: return .wpa
            default: return nil
            }
        }
    }

    private static func attempt(ssid: String,
                                password: String,
                                security: Security,
                                canReadSSID: Bool,
                                completion: @escaping (Result<Success, Error>) -> Void) {
        let configuration: NEHotspotConfiguration
        switch security {
        case .open:
            configuration = NEHotspotConfiguration(ssid: ssid)
        case .wpa:
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        case .wep:
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: true)
        }
        // false = 설정에 저장되어 다음부터 자동 재연결
        configuration.joinOnce = false

        NEHotspotConfigurationManager.shared.apply(configuration) { error in
            DispatchQueue.main.async {
                if let nsError = error as NSError? {
                    // 이미 해당 네트워크에 연결된 상태는 성공
                    if nsError.domain == NEHotspotConfigurationErrorDomain,
                       nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                        completion(.success(Success(ssid: ssid, verified: true)))
                        return
                    }
                    completion(.failure(ConnectError.message(friendlyMessage(nsError))))
                    return
                }
                verifyJoin(ssid: ssid, canReadSSID: canReadSSID) { check in
                    switch check {
                    case .joined(let actual):
                        completion(.success(Success(ssid: actual, verified: true)))
                    case .unknown:
                        // 붙었는지 알 수 없다 = 실패가 아니다.
                        // 여기서 설정을 지우면 방금 성공한 연결을 앱이 끊는 꼴이 된다.
                        completion(.success(Success(ssid: ssid, verified: false)))
                    case .notJoined:
                        // 그 이름의 네트워크가 없거나 비밀번호가 틀렸다.
                        // 설정 앱에 유령 네트워크가 쌓이지 않게 방금 넣은 설정을 되돌린다.
                        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
                        completion(.failure(ConnectError.notFound(ssid: ssid, suggestions: [])))
                    }
                }
            }
        }
    }

    private static func isNotFound(_ result: Result<Success, Error>) -> Bool {
        guard case .failure(let error) = result,
              case ConnectError.notFound = error else { return false }
        return true
    }

    // MARK: - 붙었는지 확인

    private enum JoinCheck {
        /// 확인됨. 연관값은 iOS가 알려준 실제 표기.
        case joined(String)
        /// 확인 결과 안 붙음 (다른 네트워크에 그대로 있거나, 와이파이가 아예 안 올라옴)
        case notJoined
        /// 판정 불가 — 이름을 읽을 권한이 없는데 와이파이 자체는 살아 있는 경우
        case unknown
    }

    private static func verifyJoin(ssid: String,
                                   canReadSSID: Bool,
                                   completion: @escaping (JoinCheck) -> Void) {
        guard canReadSSID else {
            // 이름을 읽을 수 없으니 '와이파이로 나가는 길이 있는지'로만 본다.
            // 길이 없으면 확실히 실패, 있으면 (예전 네트워크일 수도 있어) 판정 불가.
            wifiPathIsUp(timeout: verifyWindow) { up in
                completion(up ? .unknown : .notJoined)
            }
            return
        }
        poll(ssid: ssid, deadline: Date().addingTimeInterval(verifyWindow), completion: completion)
    }

    private static func poll(ssid: String,
                             deadline: Date,
                             completion: @escaping (JoinCheck) -> Void) {
        NEHotspotNetwork.fetchCurrent { network in
            DispatchQueue.main.async {
                if let current = network?.ssid,
                   current.caseInsensitiveCompare(ssid) == .orderedSame {
                    // 대소문자만 다르면 사실 같은 네트워크다 — iOS 표기를 정답으로 삼는다
                    completion(.joined(current))
                    return
                }
                guard Date() < deadline else {
                    completion(.notJoined)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
                    poll(ssid: ssid, deadline: deadline, completion: completion)
                }
            }
        }
    }

    /// 지금 연결된 SSID (읽을 수 없으면 nil)
    private static func currentSSID(canReadSSID: Bool, completion: @escaping (String?) -> Void) {
        guard canReadSSID else { return completion(nil) }
        NEHotspotNetwork.fetchCurrent { network in
            DispatchQueue.main.async { completion(network?.ssid) }
        }
    }

    /// 와이파이 인터페이스로 나가는 경로가 살아 있는지 — 위치 권한이 필요 없는 유일한 연결 신호.
    /// 이름은 몰라도 '와이파이가 아예 안 붙었다'는 사실은 이걸로 알 수 있다.
    private static func wifiPathIsUp(timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        let queue = DispatchQueue(label: "WifiConnector.path")
        var finished = false

        func finish(_ up: Bool) {
            queue.async {
                guard !finished else { return }
                finished = true
                monitor.cancel()
                DispatchQueue.main.async { completion(up) }
            }
        }

        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied { finish(true) }
        }
        monitor.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
    }

    // MARK: - 에러 문구

    private static func friendlyMessage(_ error: NSError) -> String {
        guard error.domain == NEHotspotConfigurationErrorDomain,
              let code = NEHotspotConfigurationError(rawValue: error.code) else {
            return error.localizedDescription
        }
        switch code {
        case .invalidSSID: return "네트워크 이름(SSID)이 올바르지 않아요."
        case .invalidWPAPassphrase: return "비밀번호 형식이 올바르지 않아요. (WPA는 8~63자)"
        case .invalidWEPPassphrase: return "비밀번호 형식이 올바르지 않아요. (WEP은 5자 또는 13자)"
        case .userDenied: return "연결 확인 창에서 '연결'을 눌러야 연결됩니다. 다시 시도해 주세요."
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
