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
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        DispatchQueue.global(qos: .userInitiated).async {
            // 언어 우선순위를 달리한 두 번의 인식을 겹쳐 읽는다.
            //
            // Vision은 한 줄을 하나의 언어 모델로 읽는데, 우선순위가 곧 그 선택을 좌우한다.
            // 영어를 앞에 두면 'KT_GIGA_3층'의 한글이 기호로 뭉개지고("KT_GIGA_3%"),
            // 한국어를 앞에 두면 반대로 영숫자 줄이 가끔 나빠진다("FREE WiFi뺀").
            // 어느 한쪽을 고르면 다른 쪽 안내판을 잃으므로, 둘 다 읽고 줄마다 나은 쪽을 쓴다.
            let korean = perform(cgImage, orientation: orientation, languages: ["ko-KR", "en-US"])
            let english = perform(cgImage, orientation: orientation, languages: ["en-US", "ko-KR"])
            let merged = merge(korean, with: english)
            DispatchQueue.main.async { completion(merged) }
        }
    }

    /// 사진에 찍힌 와이파이 QR(WIFI:S:…;T:WPA;P:…;;)을 그대로 읽어낸다.
    ///
    /// 안내판에는 QR이 함께 인쇄된 경우가 많은데, 그 QR에는 OCR이 추측할 필요가 없는
    /// 정확한 이름과 비밀번호가 들어 있다. 글자를 읽기 전에 여기부터 확인한다.
    static func decodeWifiQR(in image: UIImage, completion: @escaping (WifiCredentials?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try? handler.perform([request])

            let payloads = (request.results ?? []).compactMap { $0.payloadStringValue }
            let found = payloads.compactMap(WifiQRPayload.parse).first
            DispatchQueue.main.async { completion(found) }
        }
    }

    // MARK: - Private

    private static func perform(_ cgImage: CGImage,
                                orientation: CGImagePropertyOrientation,
                                languages: [String]) -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        // 비밀번호는 사전에 없는 문자열이므로 자동 교정을 꺼야 정확함
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let observations = request.results ?? []
        // 위에서 아래 순서로 정렬 (Vision 좌표계는 좌하단 원점)
        return observations
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return RecognizedLine(text: text, boundingBox: observation.boundingBox)
            }
    }

    /// 두 인식 결과를 같은 자리끼리 짝지어, 줄마다 더 멀쩡해 보이는 쪽을 남긴다.
    /// 한쪽에만 있는 줄은 그대로 살린다 — 못 읽은 줄이 하나라도 줄어드는 편이 낫다.
    private static func merge(_ primary: [RecognizedLine],
                              with secondary: [RecognizedLine]) -> [RecognizedLine] {
        var used = Set<Int>()
        var result: [RecognizedLine] = []

        for line in primary {
            if let idx = bestOverlap(of: line, in: secondary, excluding: used) {
                used.insert(idx)
                result.append(readability(secondary[idx].text) > readability(line.text)
                              ? secondary[idx] : line)
            } else {
                result.append(line)
            }
        }
        for (idx, line) in secondary.enumerated() where !used.contains(idx) {
            result.append(line)
        }
        return result.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    }

    /// 같은 줄로 볼 만큼 겹치는 관측을 찾는다 (세로로 겹치고 가로로도 걸치는 것).
    private static func bestOverlap(of line: RecognizedLine,
                                    in others: [RecognizedLine],
                                    excluding used: Set<Int>) -> Int? {
        var best: (index: Int, overlap: CGFloat)?
        for (idx, other) in others.enumerated() where !used.contains(idx) {
            let intersection = line.boundingBox.intersection(other.boundingBox)
            guard !intersection.isNull, intersection.height > 0 else { continue }
            let smaller = min(line.boundingBox.height, other.boundingBox.height)
            guard smaller > 0, intersection.height / smaller >= 0.5 else { continue }
            let overlap = intersection.width * intersection.height
            if overlap > (best?.overlap ?? 0) { best = (idx, overlap) }
        }
        return best?.index
    }

    /// 읽을 만한 값처럼 보일수록 높은 점수.
    ///
    /// 잘못 읽힌 줄은 글자가 사라지고 기호만 남는 특징이 뚜렷하다("1|9@: abcd1234", "ë: abcd1234").
    /// 그래서 글자·숫자의 비율을 보고, 기호 덩어리로 뭉개진 쪽을 떨어뜨린다.
    private static func readability(_ text: String) -> Double {
        let scalars = text.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) }
        guard !scalars.isEmpty else { return 0 }
        let alphanumerics = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        return Double(alphanumerics) / Double(scalars.count)
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
