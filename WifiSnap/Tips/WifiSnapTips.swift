import SwiftUI
import TipKit

/// 앱 기능을 사용자에게 순차적으로 알려주는 TipKit 팁 모음.
///
/// 흐름: 사진 스캔 → (연결되면) 연결 카드 사용법 → (저장되면) 목록 조작법 → (써 보면) 근처 추천.
/// 실제 사용 흐름을 따라가며 필요한 순간에만 하나씩 노출한다.
enum WifiSnapTips {
    /// 네트워크가 저장(연결)됐을 때 도네이션 — 목록에 다룰 대상이 생김
    static let savedNetwork = Tips.Event(id: "wifisnap.savedNetwork")
    /// 저장 목록의 행을 실제로 써 봤을 때(상세 열기·연결·공유) 도네이션
    static let usedSavedRow = Tips.Event(id: "wifisnap.usedSavedRow")
}

/// 1) 안내판·영수증을 촬영해 ID/PW 자동 인식 — 새 사용자가 가장 먼저 할 일이라 조건 없이 노출
struct ScanWifiTip: Tip {
    var title: Text { Text("사진으로 자동 입력") }
    var message: Text? {
        Text("카페·숙소의 와이파이 안내문을 촬영하거나 앨범에서 고르면, ID와 비밀번호를 알아서 읽어 연결해요.")
    }
    var image: Image? { Image(systemName: "camera.viewfinder") }
}

/// 2) 지금 연결된 와이파이 카드 사용법 — 보여주기만 하면 연결, 밀면 안내판
struct ConnectedCardTip: Tip {
    var title: Text { Text("이 카드를 보여주세요") }
    var message: Text? {
        Text("친구가 QR을 카메라로 비추면 비밀번호 없이 바로 연결돼요. 카드를 밀거나 탭하면 손님용 안내판 미리보기로 뒤집혀요.")
    }
    var image: Image? { Image(systemName: "qrcode") }
}

/// 2-1) 스캔 결과 편집 — 조각을 끌어다 놓는 방식은 알려주지 않으면 모른다
struct CredentialPuzzleTip: Tip {
    var title: Text { Text("끌어다 놓아 고치기") }
    var message: Text? {
        Text("아래 조각을 아이디·비밀번호 칸으로 끌어다 놓으세요. 둘이 뒤바뀌었으면 칸끼리 서로 끌면 자리가 바뀌어요.")
    }
    var image: Image? { Image(systemName: "hand.point.up.left") }
}

/// 3) 저장 목록 행 조작법 — 탭·스와이프는 눈에 보이지 않아 안내가 필요하다
struct SavedRowActionsTip: Tip {
    var title: Text { Text("목록에서 바로 쓰기") }
    var message: Text? {
        Text("행을 탭하면 QR·상세가 열려요. 오른쪽으로 밀면 이 폰 연결, 왼쪽으로 밀면 QR 공유예요.")
    }
    var image: Image? { Image(systemName: "hand.draw") }

    var rules: [Rule] {
        // 목록에 다룰 네트워크가 하나라도 있어야 의미가 있음
        #Rule(WifiSnapTips.savedNetwork) { $0.donations.count > 0 }
    }
}

/// 4) 위치 기반 근처 와이파이 자동 추천
struct NearbyWifiTip: Tip {
    var title: Text { Text("근처 와이파이 먼저") }
    var message: Text? {
        Text("저장한 와이파이는 위치와 함께 기억돼요. 그 장소에 다시 오면 목록 맨 위로 올라오고 '📍 근처' 뱃지가 붙어요.")
    }
    var image: Image? { Image(systemName: "location.fill") }

    var rules: [Rule] {
        #Rule(WifiSnapTips.savedNetwork) { $0.donations.count > 0 }
        // 목록 조작법을 먼저 익힌 뒤에 안내 — 팁 두 개가 한꺼번에 뜨지 않게
        #Rule(WifiSnapTips.usedSavedRow) { $0.donations.count > 0 }
    }
}
