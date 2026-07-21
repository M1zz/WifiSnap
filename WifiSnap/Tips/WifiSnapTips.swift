import SwiftUI
import TipKit

/// 앱 기능을 사용자에게 순차적으로 알려주는 TipKit 팁 모음.
///
/// 흐름: 공유 → (공유해 보면) 사진 스캔 → (저장하면) 근처 추천 순으로
/// 실제 사용 흐름을 따라가며 필요한 순간에만 하나씩 노출한다.
enum WifiSnapTips {
    /// 사용자가 QR 공유 기능을 한 번 써 봤을 때 도네이션
    static let usedShare = Tips.Event(id: "wifisnap.usedShare")
    /// 네트워크가 저장(연결/공유)됐을 때 도네이션 — 목록에 추천할 대상이 생김
    static let savedNetwork = Tips.Event(id: "wifisnap.savedNetwork")
}

/// 1) 지금 연결된 와이파이를 친구에게 QR로 공유
struct ShareWifiTip: Tip {
    var title: Text { Text("친구에게 와이파이 공유") }
    var message: Text? {
        Text("지금 연결된 와이파이를 QR로 만들면, 상대가 카메라로 찍어 비밀번호 없이 바로 접속해요.")
    }
    var image: Image? { Image(systemName: "qrcode") }
}

/// 2) 안내판·영수증을 촬영해 ID/PW 자동 인식
struct ScanWifiTip: Tip {
    var title: Text { Text("사진으로 자동 입력") }
    var message: Text? {
        Text("카페·숙소의 와이파이 안내문을 촬영하거나 앨범에서 고르면, ID와 비밀번호를 알아서 읽어 연결해요.")
    }
    var image: Image? { Image(systemName: "camera.viewfinder") }

    var rules: [Rule] {
        // 공유를 한 번 경험한 뒤, 다음 기능으로 스캔을 안내
        #Rule(WifiSnapTips.usedShare) { $0.donations.count > 0 }
    }
}

/// 3) 위치 기반 근처 와이파이 자동 추천
struct NearbyWifiTip: Tip {
    var title: Text { Text("근처 와이파이 먼저") }
    var message: Text? {
        Text("저장한 와이파이는 위치와 함께 기억돼요. 그 장소에 다시 오면 목록 맨 위로 올라오고 '📍 근처' 뱃지가 붙어요.")
    }
    var image: Image? { Image(systemName: "location.fill") }

    var rules: [Rule] {
        // 목록에 추천할 네트워크가 하나라도 생겼을 때만 의미가 있음
        #Rule(WifiSnapTips.savedNetwork) { $0.donations.count > 0 }
    }
}
