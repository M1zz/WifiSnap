import SwiftUI

/// '설정 > Wi-Fi' 화면 캡처에서 와이파이 이름을 가져오는 화면.
///
/// iOS는 기기가 아는 와이파이 목록을 앱에 주지 않는다. 그래서 사용자가 그 화면을 캡처해 주면
/// 읽어낸 이름을 여기서 확인·수정한 뒤 선택 목록에 넣는다. 인식이 완벽할 수 없으므로
/// 모든 이름을 켜고 끄고 고칠 수 있게 하는 것이 이 화면의 핵심이다.
struct WifiListImportSheet: View {
    @ObservedObject var store: KnownSSIDStore
    @Environment(\.dismiss) private var dismiss

    /// 화면에서 읽어낸 이름 한 줄 (체크·편집 가능)
    private struct Candidate: Identifiable {
        let id = UUID()
        var name: String
        var isSelected: Bool = true
    }

    @State private var candidates: [Candidate] = []
    @State private var isRecognizing = false
    @State private var showPicker = false
    @State private var didScan = false
    @State private var manualName = ""

    var body: some View {
        NavigationStack {
            Form {
                howToSection
                if isRecognizing {
                    Section { recognizingRow }
                } else if !candidates.isEmpty {
                    candidateSection
                } else if didScan {
                    Section { emptyResultRow }
                }
                manualSection
                savedSection
            }
            .navigationTitle("와이파이 목록 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("추가") { addSelected() }
                        .font(.body.weight(.semibold))
                        .disabled(selectedNames.isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                ImagePicker(source: .library) { image in scan(image) }
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Sections

    private var howToSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("아이폰 '설정 > Wi-Fi' 화면을 캡처한 뒤 그 사진을 고르면, 목록에 있는 이름을 읽어옵니다.")
                    .font(.subheadline)
                Text("iOS는 저장된 와이파이 목록을 앱에 알려주지 않아서, 캡처가 유일한 방법이에요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showPicker = true
                } label: {
                    Label(didScan ? "다른 캡처 고르기" : "캡처 고르기", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    private var recognizingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("이름 읽는 중…").foregroundStyle(.secondary)
        }
    }

    private var emptyResultRow: some View {
        Text("이름을 찾지 못했어요. 목록이 잘 보이게 다시 캡처하거나, 아래에서 직접 적어 주세요.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var candidateSection: some View {
        Section {
            ForEach($candidates) { $candidate in
                HStack(spacing: 10) {
                    Button {
                        candidate.isSelected.toggle()
                    } label: {
                        Image(systemName: candidate.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(candidate.isSelected ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    // 인식이 틀렸을 수 있으니 이름을 그 자리에서 고칠 수 있게 한다
                    TextField("와이파이 이름", text: $candidate.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Text("읽어낸 이름 \(candidates.count)개")
        } footer: {
            Text("맞는 것만 켜 두고, 틀린 글자는 눌러서 고친 뒤 오른쪽 위 '추가'를 누르세요.")
        }
    }

    private var manualSection: some View {
        Section("직접 적어 넣기") {
            HStack(spacing: 8) {
                TextField("와이파이 이름", text: $manualName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("추가") {
                    store.add([manualName])
                    manualName = ""
                }
                .font(.subheadline.weight(.semibold))
                .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        if !store.ssids.isEmpty {
            Section("가져온 이름 \(store.ssids.count)개") {
                ForEach(store.ssids, id: \.self) { ssid in
                    Text(ssid)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.remove(ssid)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Actions

    private var selectedNames: [String] {
        candidates
            .filter { $0.isSelected }
            .map { $0.name.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func scan(_ image: UIImage) {
        isRecognizing = true
        didScan = true
        candidates = []
        TextRecognizer.recognize(in: image) { lines in
            candidates = WifiListParser.ssids(from: lines).map { Candidate(name: $0) }
            isRecognizing = false
        }
    }

    private func addSelected() {
        store.add(selectedNames)
        // 추가한 것은 후보 목록에서 비워 중복 추가를 막는다
        candidates.removeAll { $0.isSelected }
        if candidates.isEmpty { dismiss() }
    }
}
