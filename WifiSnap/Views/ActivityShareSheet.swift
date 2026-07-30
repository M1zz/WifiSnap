import SwiftUI
import UIKit

/// UIActivityViewController 래퍼 — 이미지 저장/공유/AirPrint 인쇄를 한 번에 제공.
/// ShareLink를 쓸 수 없는 자리(예: List의 스와이프 액션)에서 시스템 공유 시트를 띄울 때 사용한다.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
