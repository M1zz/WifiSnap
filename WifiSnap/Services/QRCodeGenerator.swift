import UIKit
import CoreImage.CIFilterBuiltins

/// 표준 WiFi QR 문자열(WIFI:S:...;T:WPA;P:...;;)과 QR 이미지를 생성
/// 이 QR을 아이폰/안드로이드 기본 카메라로 비추면 바로 연결 제안이 뜸
enum QRCodeGenerator {

    /// CIContext 생성은 비용이 크므로 한 번만 만들어 재사용
    private static let context = CIContext()

    /// 표준 포맷의 특수문자(\ ; , : ")는 백슬래시로 이스케이프해야 함
    static func wifiString(ssid: String, password: String) -> String {
        func escape(_ text: String) -> String {
            var escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            for character in [";", ",", ":", "\""] {
                escaped = escaped.replacingOccurrences(of: character, with: "\\" + character)
            }
            return escaped
        }
        if password.isEmpty {
            return "WIFI:S:\(escape(ssid));T:nopass;;"
        }
        return "WIFI:S:\(escape(ssid));T:WPA;P:\(escape(password));;"
    }

    static func qrImage(for text: String, scale: CGFloat = 14) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    static func wifiQRImage(ssid: String, password: String) -> UIImage? {
        qrImage(for: wifiString(ssid: ssid, password: password))
    }
}
