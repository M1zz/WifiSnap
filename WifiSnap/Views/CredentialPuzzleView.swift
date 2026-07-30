import SwiftUI
import TipKit

/// 사진에서 읽은 조각을 아이디·비밀번호 칸에 끌어다 놓는 퍼즐형 편집기.
///
/// OCR이 아이디와 비밀번호를 바꿔 읽는 일이 흔한데, 그때 지우고 다시 타이핑하는 대신
/// 맞는 조각을 칸으로 끌어다 놓으면 끝나게 한다. 칸끼리도 서로 끌어 옮길 수 있어
/// 둘이 뒤바뀐 경우를 두 번의 드래그로 고칠 수 있다.
struct CredentialPuzzleView: View {

    /// 조각 묶음 (사진에서 읽은 값 / 이 폰이 아는 이름 …)
    struct TokenGroup: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tokens: [String]
    }

    let groups: [TokenGroup]
    @Binding var ssid: String
    @Binding var password: String

    private enum Slot { case ssid, password }

    @State private var targeted: Slot?
    private let puzzleTip = CredentialPuzzleTip()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TipView(puzzleTip)

            slot(.ssid)
            slot(.password)

            ForEach(groups) { group in
                tokenGroup(group)
            }
        }
    }

    // MARK: - 칸

    @ViewBuilder
    private func slot(_ slot: Slot) -> some View {
        let value = binding(for: slot)
        let isTargeted = targeted == slot

        HStack(spacing: 10) {
            Image(systemName: slot == .ssid ? "wifi" : "key.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(isTargeted ? Color.orange : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(slot == .ssid ? "아이디" : "비밀번호")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                // 끌어다 놓기와 별개로 직접 고칠 수도 있어야 한다
                TextField("조각을 끌어다 놓거나 입력", text: value)
                    .font(.body.weight(.medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if !value.wrappedValue.isEmpty {
                Button {
                    value.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isTargeted ? Color.orange.opacity(0.14) : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.orange : .clear, lineWidth: 2)
        }
        .animation(.snappy(duration: 0.15), value: isTargeted)
        // 칸에 있는 값도 다른 칸으로 끌어 옮길 수 있게 (아이디↔비밀번호 뒤바뀜 교정)
        .ifLet(value.wrappedValue.isEmpty ? nil : value.wrappedValue) { view, text in
            view.draggable(text)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dropped = items.first else { return false }
            drop(dropped, into: slot)
            return true
        } isTargeted: { hovering in
            targeted = hovering ? slot : (targeted == slot ? nil : targeted)
        }
    }

    private func binding(for slot: Slot) -> Binding<String> {
        slot == .ssid ? $ssid : $password
    }

    /// 조각을 칸에 넣는다. 다른 칸에 있던 값을 끌어 온 경우 두 값을 맞바꾼다.
    private func drop(_ value: String, into slot: Slot) {
        let previous = binding(for: slot).wrappedValue
        switch slot {
        case .ssid:
            if password == value { password = previous }
            ssid = value
        case .password:
            if ssid == value { ssid = previous }
            password = value
        }
        puzzleTip.invalidate(reason: .actionPerformed)
    }

    // MARK: - 조각 풀

    private func tokenGroup(_ group: TokenGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(group.title, systemImage: group.icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(group.tokens, id: \.self) { token in
                    tokenChip(token)
                }
            }
        }
    }

    private func tokenChip(_ token: String) -> some View {
        let isUsed = token == ssid || token == password
        return Text(token)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isUsed ? Color.orange.opacity(0.2) : Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(isUsed ? Color.orange : .primary)
            .overlay {
                Capsule().strokeBorder(isUsed ? Color.orange.opacity(0.5) : .clear, lineWidth: 1)
            }
            .draggable(token)
    }
}

// MARK: - 흐름 레이아웃

/// 폭이 제각각인 칩을 줄바꿈하며 채우는 레이아웃.
/// 퍼즐 조각은 전부 한눈에 보여야 해서 가로 스크롤 대신 여러 줄로 편다.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension View {
    /// 값이 있을 때만 모디파이어를 붙인다 (빈 칸은 끌 수 없어야 하므로)
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?,
                                 @ViewBuilder transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
