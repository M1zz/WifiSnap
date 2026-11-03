import SwiftUI
import UIKit

extension View {
    /// QR을 보여 주는 동안 화면을 가장 밝게 한다.
    /// 어두운 화면에 띄운 QR은 상대 카메라가 잘 못 읽는다.
    func brightensForQR(_ isOn: Bool = true) -> some View {
        modifier(QRBrightness(isOn: isOn))
    }
}

/// 나타나면 밝기를 올리고, 사라지거나 앱이 뒤로 가면 원래 밝기로 돌려 놓는다.
private struct QRBrightness: ViewModifier {
    let isOn: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var original: CGFloat?

    func body(content: Content) -> some View {
        content
            .onAppear { if isOn { raise() } }
            .onDisappear { restore() }
            // 제어 센터를 내리는 정도(inactive)로는 건드리지 않는다 — 거기서 밝기를 바꿀 수도 있다
            .onChange(of: scenePhase) { _, phase in
                guard isOn else { return }
                if phase == .active { raise() }
                if phase == .background { restore() }
            }
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    private func raise() {
        guard original == nil, let screen else { return }
        original = screen.brightness
        screen.brightness = 1
    }

    private func restore() {
        guard let original else { return }
        screen?.brightness = original
        self.original = nil
    }
}
