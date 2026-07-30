import Vision
import UIKit

/// 인식된 한 줄. 위치를 함께 들고 있어야 화면 캡처에서
/// 왼쪽 정렬된 항목(와이파이 이름)과 오른쪽 상태 텍스트를 구분할 수 있다.
struct RecognizedLine {
    let text: String
    /// Vision 좌표계(좌하단 원점, 0~1 정규화)
    let boundingBox: CGRect
}

/// Vision 프레임워크로 사진 속 텍스트를 줄 단위로 인식
enum TextRecognizer {

    /// 텍스트만 필요한 곳(안내판 OCR)에서 쓰는 간편 버전
    static func recognizeLines(in image: UIImage, completion: @escaping ([String]) -> Void) {
        recognize(in: image) { lines in completion(lines.map(\.text)) }
    }

    static func recognize(in image: UIImage, completion: @escaping ([RecognizedLine]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let request = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            // 위에서 아래 순서로 정렬 (Vision 좌표계는 좌하단 원점)
            let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            let lines = sorted.compactMap { observation -> RecognizedLine? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return RecognizedLine(text: text, boundingBox: observation.boundingBox)
            }
            DispatchQueue.main.async { completion(lines) }
        }
        request.recognitionLevel = .accurate
        // 영어 우선 — 와이파이 이름·비밀번호는 거의 라틴 문자·숫자다.
        // 한국어는 라벨("비밀번호", "네트워크")과 설정 화면 문구를 읽기 위해 함께 둔다.
        request.recognitionLanguages = ["en-US", "ko-KR"]
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
