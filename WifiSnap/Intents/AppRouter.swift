import Foundation

/// 앱 밖(단축어·Siri·Spotlight)에서 들어온 요청을 메인 화면에 넘기는 우편함.
///
/// 인텐트의 perform() 은 화면이 뜨기 전에 불릴 수 있다. 그래서 바로 화면을 조작하지 않고
/// 요청을 여기 남겨 두면, ContentView 가 나타나는 즉시(또는 이미 떠 있으면 그 자리에서) 꺼내 처리한다.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Route: Equatable {
        /// 지금 연결된 와이파이(없으면 가장 최근에 저장한 것)의 QR 상세를 연다
        case showWifiQR
        /// 와이파이 안내문 촬영을 바로 시작한다
        case scanWifiPhoto
    }

    @Published var pending: Route?

    private init() {}
}
