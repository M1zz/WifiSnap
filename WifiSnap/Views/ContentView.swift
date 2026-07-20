import SwiftUI

struct ContentView: View {
    @StateObject private var store = NetworkStore()
    @StateObject private var currentNetwork = CurrentNetworkService()

    // 내 와이파이 공유 상태
    @State private var sharePassword = ""
    @State private var shareSSID = ""   // 자동 감지 실패 시 직접 입력용

    // 스캔 & 편집 상태
    @State private var credentials = WifiCredentials()
    @State private var recognizedLines: [String] = []
    @State private var isRecognizing = false

    // 시트 상태 (한 뷰에 .sheet를 여러 개 붙이면 충돌하므로 enum 하나로 통합)
    @State private var activeSheet: ActiveSheet?

    // 연결 상태
    @State private var isConnecting = false
    @State private var statusMessage: StatusMessage?

    enum ActiveSheet: Identifiable {
        case picker(ImagePicker.Source)
        case qr(SavedNetwork)

        var id: String {
            switch self {
            case .picker(let source): return "picker-\(source.id)"
            case .qr(let network): return "qr-\(network.id)"
            }
        }
    }

    struct StatusMessage: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        NavigationStack {
            List {
                shareSection
                scanSection
                if isRecognizing || !recognizedLines.isEmpty || hasInput {
                    resultSection
                }
                savedSection
            }
            .listSectionSpacing(24)
            .navigationTitle("WifiSnap")
            .onAppear {
                currentNetwork.refresh()
            }
            .onChange(of: currentNetwork.currentSSID) { _, newSSID in
                // 이전에 저장해둔 네트워크면 비밀번호 자동 채움 → 바로 QR 가능
                if let ssid = newSSID,
                   let saved = store.networks.first(where: { $0.ssid == ssid }) {
                    sharePassword = saved.password
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .picker(let source):
                    ImagePicker(source: source) { image in
                        runOCR(on: image)
                    }
                    .ignoresSafeArea()
                case .qr(let network):
                    QRCodeSheet(ssid: network.ssid, password: network.password)
                }
            }
            .alert(item: $statusMessage) { message in
                Alert(title: Text(message.isError ? "연결 실패" : "완료"),
                      message: Text(message.text),
                      dismissButton: .default(Text("확인")))
            }
        }
    }

    private var hasInput: Bool {
        !credentials.ssid.isEmpty || !credentials.password.isEmpty
    }

    /// 자동 감지된 SSID가 있으면 그것, 없으면 직접 입력값
    private var effectiveShareSSID: String {
        currentNetwork.currentSSID ?? shareSSID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Sections

    /// 지금 연결된 와이파이를 친구에게 QR로 공유
    private var shareSection: some View {
        Section {
            if let ssid = currentNetwork.currentSSID {
                // 자동 감지 성공 (실기기 + 권한 허용)
                HStack {
                    Image(systemName: "wifi")
                        .foregroundStyle(.green)
                    Text(ssid)
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text("연결됨")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // 자동 감지 실패(시뮬레이터/권한/미지원) → 직접 입력으로 대체
                TextField("와이파이 이름 (SSID) 직접 입력", text: $shareSSID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    currentNetwork.refresh()
                } label: {
                    Label("현재 연결된 와이파이 자동 감지", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if currentNetwork.permissionDenied {
                    Label("자동 감지하려면 설정 → 개인정보 보호 → 위치 서비스에서 WifiSnap을 허용해 주세요.",
                          systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("비밀번호 (최초 1회만 입력)", text: $sharePassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !effectiveShareSSID.isEmpty && sharePassword.isEmpty {
                Label("iOS 보안상 이미 연결돼 있어도 앱은 비밀번호를 읽을 수 없어요. 위에 한 번만 입력하면 아래 버튼이 켜집니다.",
                      systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                let name = effectiveShareSSID
                let network = SavedNetwork(ssid: name, password: sharePassword)
                store.upsert(ssid: name, password: sharePassword)
                activeSheet = .qr(network)
            } label: {
                Label("친구에게 보여줄 QR 만들기", systemImage: "qrcode")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(effectiveShareSSID.isEmpty || sharePassword.isEmpty)
        } header: {
            Text("내 와이파이 공유")
        } footer: {
            Text("친구가 기본 카메라로 QR을 비추면 탭 한 번에 연결돼요. iOS 보안상 비밀번호는 앱이 읽을 수 없어 처음 한 번만 직접 입력해요. (설정 → Wi-Fi → ⓘ → 암호에서 복사 가능)")
        }
    }

    private var scanSection: some View {
        Section {
            Button {
                activeSheet = .picker(.camera)
            } label: {
                Label(ImagePicker.isCameraAvailable ? "안내판 촬영하기" : "카메라를 쓸 수 없어요 (실기기 필요)",
                      systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!ImagePicker.isCameraAvailable)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))
            .listRowBackground(Color.clear)

            Button {
                activeSheet = .picker(.library)
            } label: {
                Label("앨범에서 선택", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        } footer: {
            Text("ID/PW가 적힌 와이파이 안내판을 찍으면 자동으로 인식해요.")
        }
    }

    private var resultSection: some View {
        Section("인식 결과 (수정 가능)") {
            if isRecognizing {
                HStack {
                    ProgressView()
                    Text("텍스트 인식 중…").foregroundStyle(.secondary)
                }
            } else {
                TextField("네트워크 이름 (SSID)", text: $credentials.ssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("비밀번호", text: $credentials.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    connect()
                } label: {
                    if isConnecting {
                        HStack {
                            ProgressView()
                            Text("연결 중…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("와이파이 연결", systemImage: "wifi")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(credentials.ssid.isEmpty || isConnecting)
            }
        }
    }

    private var savedSection: some View {
        Section {
            if store.networks.isEmpty {
                Text("아직 저장된 네트워크가 없어요.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.networks) { network in
                    HStack {
                        Button {
                            credentials = WifiCredentials(ssid: network.ssid,
                                                          password: network.password)
                            connect()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(network.ssid).font(.body.weight(.medium))
                                Text(network.savedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            activeSheet = .qr(network)
                        } label: {
                            Image(systemName: "qrcode")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { store.delete(at: $0) }
            }
        } header: {
            Text("저장된 네트워크")
        } footer: {
            Text("항목을 탭하면 다시 연결, QR 아이콘을 탭하면 다른 사람과 공유할 수 있는 연결용 QR이 만들어져요.")
        }
    }

    // MARK: - Actions

    private func runOCR(on image: UIImage) {
        isRecognizing = true
        recognizedLines = []
        TextRecognizer.recognizeLines(in: image) { lines in
            recognizedLines = lines
            credentials = WifiCredentialParser.parse(lines: lines)
            isRecognizing = false
            if credentials.ssid.isEmpty && credentials.password.isEmpty {
                statusMessage = StatusMessage(
                    text: "사진에서 ID/PW를 찾지 못했어요. 더 가까이서 선명하게 찍어보세요.",
                    isError: true
                )
            }
        }
    }

    private func connect() {
        guard !credentials.ssid.isEmpty else { return }
        isConnecting = true
        WifiConnector.connect(ssid: credentials.ssid,
                              password: credentials.password) { result in
            isConnecting = false
            switch result {
            case .success:
                store.upsert(ssid: credentials.ssid, password: credentials.password)
                statusMessage = StatusMessage(
                    text: "'\(credentials.ssid)'에 연결했어요.",
                    isError: false
                )
            case .failure(let error):
                statusMessage = StatusMessage(text: error.localizedDescription, isError: true)
            }
        }
    }
}

extension ImagePicker.Source: Identifiable {
    var id: String {
        switch self {
        case .camera: return "camera"
        case .library: return "library"
        }
    }
}

#Preview {
    ContentView()
}
