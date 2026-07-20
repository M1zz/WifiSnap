import Vision
import UIKit

/// Vision 프레임워크로 사진 속 텍스트를 줄 단위로 인식
enum TextRecognizer {

    static func recognizeLines(in image: UIImage, completion: @escaping ([String]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let request = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            // 위에서 아래 순서로 정렬 (Vision 좌표계는 좌하단 원점)
            let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async { completion(lines) }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        // 비밀번호는 사전에 없는 문자열이므로 자동 교정을 꺼야 정확함
        request.usesLanguageCorrection = false

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation)
            )
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
