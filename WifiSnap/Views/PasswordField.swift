import SwiftUI

/// 눈 버튼으로 비밀번호를 표시/숨김 전환할 수 있는 입력 필드
struct PasswordField: View {
    let placeholder: String
    @Binding var text: String

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .focused($isFocused)

            Button {
                isRevealed.toggle()
                // 표시 전환 후에도 계속 입력할 수 있도록 포커스 유지
                isFocused = true
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isRevealed ? "비밀번호 숨기기" : "비밀번호 표시")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }
}
