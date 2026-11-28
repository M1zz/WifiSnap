import SwiftUI
import AppKit

/// 안내판을 종이 한 장에 맞춰 인쇄한다. 아이폰의 안내판과 같은 그림(`WifiPosterView`)을 쓴다.
@MainActor
enum MacPosterPrinter {
    static func print(_ poster: WifiPosterView, title: String) {
        let renderer = ImageRenderer(content: poster
            .environment(\.layoutDirection, Locale.app.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.locale, .app))
        // 종이 폭에 맞춰 키워도 QR 이 흐려지지 않게 넉넉한 해상도로 그린다
        renderer.scale = 6
        guard let image = renderer.nsImage else { return }

        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.orientation = .portrait
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true

        // 여백 안쪽에 비율을 지켜 가득 채운다
        let area = NSSize(width: info.paperSize.width - info.leftMargin - info.rightMargin,
                          height: info.paperSize.height - info.topMargin - info.bottomMargin)
        let ratio = min(area.width / image.size.width, area.height / image.size.height)
        let view = NSImageView(frame: NSRect(x: 0, y: 0,
                                             width: image.size.width * ratio,
                                             height: image.size.height * ratio))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        NSApp.activate(ignoringOtherApps: true)
        operation.run()
    }
}
