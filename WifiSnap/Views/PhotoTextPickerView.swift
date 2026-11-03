import SwiftUI

/// 찍은 사진 위를 손가락으로 문질러 아이디·비밀번호를 고르는 화면.
///
/// 글자 해석이 아이디와 비밀번호를 엉뚱하게 짚었을 때, 사람은 사진을 보면 어느 게 값인지 바로 안다.
/// 그 판단을 그대로 받는다 — 값 위를 문지르면 그 낱말들이 골라지고, [아이디로]/[비밀번호로]를 누르면 끝.
struct PhotoTextPickerView: View {
    let image: UIImage
    @Binding var ssid: String
    @Binding var password: String
    @Environment(\.dismiss) private var dismiss

    /// 사진의 낱말들 (읽는 순서)
    private struct Word {
        let text: String
        /// Vision 좌표계(좌하단 원점, 0~1 정규화)
        let box: CGRect
        let line: Int
        let spaceBefore: Bool
    }

    @State private var words: [Word] = []
    @State private var isRecognizing = true
    /// 고른 낱말 (words의 위치)
    @State private var selected: Set<Int> = []
    /// 지금 문지르는 중인지 — 새로 문지르기 시작하면 앞의 선택을 지운다
    @State private var isStroking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("값 위를 손가락으로 문질러 고르세요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                photo
                    .frame(maxHeight: .infinity)

                panel
            }
            .padding()
            .navigationTitle("사진에서 고르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        // 사진 위를 아래로 문지르다 시트가 닫히지 않게 — 닫기는 [완료]로
        .interactiveDismissDisabled()
        .task { recognize() }
    }

    // MARK: - 사진

    private var photo: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    ZStack(alignment: .topLeading) {
                        ForEach(words.indices, id: \.self) { index in
                            let rect = viewRect(words[index].box, in: size)
                            let isOn = selected.contains(index)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isOn ? Color.orange.opacity(0.4) : Color.white.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(isOn ? Color.orange : Color.white.opacity(0.6), lineWidth: isOn ? 2 : 1)
                                }
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in rub(at: value.location, in: size) }
                            .onEnded { _ in isStroking = false }
                    )
                }
            }
            .overlay {
                if isRecognizing { ProgressView().controlSize(.large) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)   // 문지르기 대신 아래 목록과 퍼즐 조각으로 고른다
    }

    /// Vision 좌표(좌하단 원점, 0~1)를 화면 좌표로
    private func viewRect(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: box.minX * size.width,
               y: (1 - box.maxY) * size.height,
               width: box.width * size.width,
               height: box.height * size.height)
    }

    private func rub(at point: CGPoint, in size: CGSize) {
        if !isStroking {
            isStroking = true
            selected = []
        }
        // 손가락은 글자보다 굵다 — 낱말 상자를 조금 넓혀서 맞춘다
        for index in words.indices where !selected.contains(index) {
            if viewRect(words[index].box, in: size).insetBy(dx: -6, dy: -8).contains(point) {
                selected.insert(index)
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    // MARK: - 고른 값

    /// 고른 낱말을 읽는 순서로 잇는다. 같은 줄에서 바로 이어진 낱말은 원래 띄어쓰기를 살린다.
    private var selectedText: String {
        var text = ""
        var previous: Int?
        for index in selected.sorted() {
            if let previous {
                let adjacent = index == previous + 1 && words[index].line == words[previous].line
                text += adjacent ? (words[index].spaceBefore ? " " : "") : " "
            }
            text += words[index].text
            previous = index
        }
        return text
    }

    private var panel: some View {
        let value = selectedText
        return VStack(alignment: .leading, spacing: 10) {
            Text(value.isEmpty ? " " : value)
                .font(.title3.monospaced().weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Button {
                    ssid = value
                    selected = []
                } label: {
                    Label("아이디로 넣기", systemImage: "wifi").frame(maxWidth: .infinity, minHeight: 40)
                }
                Button {
                    password = value
                    selected = []
                } label: {
                    Label("비밀번호로 넣기", systemImage: "key.fill").frame(maxWidth: .infinity, minHeight: 40)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(value.isEmpty)

            current(icon: "wifi", label: String(localized: "아이디"), value: ssid)
            current(icon: "key.fill", label: String(localized: "비밀번호"), value: password)
        }
    }

    private func current(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(value.isEmpty ? Color.secondary : .orange)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "…" : value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 인식

    private func recognize() {
        TextRecognizer.recognize(in: image) { lines in
            words = lines.enumerated().flatMap { lineIndex, line in
                line.words.map { Word(text: $0.text, box: $0.boundingBox, line: lineIndex, spaceBefore: $0.spaceBefore) }
            }
            isRecognizing = false
        }
    }
}
