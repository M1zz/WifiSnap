import SwiftUI

/// 만들어 둔 안내판 목록. 매장·자리마다 다른 안내판을 여러 장 두고 골라 쓴다.
///
/// 안내판이 문서 단위라야 공들여 맞춘 문구를 잃을 걱정 없이 새 디자인을 시험할 수 있고,
/// "비밀번호 바꿨으니 다시 뽑자"로 다시 열 이유도 생긴다.
struct PosterListSheet: View {
    @ObservedObject var store: PosterDesignStore
    let ssid: String
    let password: String

    @Environment(\.dismiss) private var dismiss
    @State private var editing: PosterDesign?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.designs) { design in
                        Button { editing = design } label: { row(design) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.delete(id: design.id)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                                Button {
                                    editing = store.duplicate(design)
                                } label: {
                                    Label("복제", systemImage: "doc.on.doc")
                                }
                                .tint(.indigo)
                            }
                    }
                } footer: {
                    Text("메인 화면 카드에는 가장 최근에 고친 안내판이 보여요. 왼쪽으로 밀면 복제·삭제할 수 있어요.")
                }
            }
            .navigationTitle("내 안내판")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = store.addNew()
                    } label: {
                        Label("새 안내판", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { design in
                WifiPosterSheet(ssid: ssid, password: password, store: store, design: design)
            }
        }
    }

    private func row(_ design: PosterDesign) -> some View {
        HStack(spacing: 12) {
            // 테마 색으로 어떤 디자인인지 한눈에
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(design.theme.gradient)
                .frame(width: 40, height: 52)
                .overlay {
                    Image(systemName: "wifi")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(design.theme.foreground)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(design.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if !design.summary.isEmpty {
                    Text(design.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(design.layout.label)
                    if !design.visibleExtraLines.isEmpty {
                        Text("직접 쓴 줄 \(design.visibleExtraLines.count)개")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
