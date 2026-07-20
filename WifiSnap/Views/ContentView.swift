import SwiftUI
import CoreLocation

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
        VStack(spacing: 12) {
            shareCard
            scanCard
            if isRecognizing || !recognizedLines.isEmpty || hasInput {
                resultCard
            }
            savedCard
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear { currentNetwork.refresh() }
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
                ImagePicker(source: source) { image in runOCR(on: image) }
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

    private var hasInput: Bool {
        !credentials.ssid.isEmpty || !credentials.password.isEmpty
    }

    /// 자동 감지된 SSID가 있으면 그것, 없으면 직접 입력값
    private var effectiveShareSSID: String {
        currentNetwork.currentSSID ?? shareSSID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cards

    /// 지금 연결된 와이파이를 친구에게 QR로 공유
    private var shareCard: some View {
        card {
            if let ssid = currentNetwork.currentSSID {
                HStack(spacing: 8) {
                    Image(systemName: "wifi").foregroundStyle(.green)
                    Text(ssid).font(.body.weight(.semibold))
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    TextField("와이파이 이름 (SSID)", text: $shareSSID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button {
                        currentNetwork.refresh()
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.bordered)
                }
            }

            SecureField("비밀번호", text: $sharePassword)
                .textFieldStyle(.roundedBorder)

            Button {
                let name = effectiveShareSSID
                let here = currentNetwork.currentLocation?.coordinate
                store.upsert(ssid: name, password: sharePassword,
                             latitude: here?.latitude, longitude: here?.longitude)
                let network = SavedNetwork(ssid: name, password: sharePassword,
                                           latitude: here?.latitude, longitude: here?.longitude)
                activeSheet = .qr(network)
            } label: {
                Label("QR 만들기", systemImage: "qrcode")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(effectiveShareSSID.isEmpty || sharePassword.isEmpty)
        }
    }

    private var scanCard: some View {
        card {
            HStack(spacing: 10) {
                Button {
                    activeSheet = .picker(.camera)
                } label: {
                    Label("촬영", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ImagePicker.isCameraAvailable)

                Button {
                    activeSheet = .picker(.library)
                } label: {
                    Label("앨범", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var resultCard: some View {
        card {
            if isRecognizing {
                HStack {
                    ProgressView()
                    Text("인식 중…").foregroundStyle(.secondary)
                }
            } else {
                TextField("SSID", text: $credentials.ssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("비밀번호", text: $credentials.password)
                    .textFieldStyle(.roundedBorder)

                Button {
                    connect()
                } label: {
                    if isConnecting {
                        HStack { ProgressView(); Text("연결 중…") }
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("연결", systemImage: "wifi")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(credentials.ssid.isEmpty || isConnecting)
            }
        }
    }

    private var savedCard: some View {
        card {
            if store.networks.isEmpty {
                Text("저장된 네트워크 없음")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(sortedNetworks) { network in
                            savedRow(network)
                            if network.id != sortedNetworks.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func savedRow(_ network: SavedNetwork) -> some View {
        HStack {
            Button {
                credentials = WifiCredentials(ssid: network.ssid, password: network.password)
                connect()
            } label: {
                HStack(spacing: 6) {
                    Text(network.ssid).font(.body.weight(.medium))
                    if let tag = nearbyTag(for: network) {
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                activeSheet = .qr(network)
            } label: {
                Image(systemName: "qrcode").font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(role: .destructive) {
                store.delete(ids: [network.id])
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    // MARK: - Location helpers

    /// 근처로 볼 반경(m)
    private let nearbyRadius: CLLocationDistance = 150

    /// 현재 위치 기준: 반경 안의 네트워크를 거리순으로 맨 위에, 나머지는 최근 저장순
    private var sortedNetworks: [SavedNetwork] {
        guard let here = currentNetwork.currentLocation else { return store.networks }
        let tagged = store.networks.map { (net: $0, dist: $0.distance(from: here)) }
        let nearby = tagged
            .filter { ($0.dist ?? .greatestFiniteMagnitude) <= nearbyRadius }
            .sorted { ($0.dist ?? 0) < ($1.dist ?? 0) }
        let rest = tagged
            .filter { ($0.dist ?? .greatestFiniteMagnitude) > nearbyRadius }
            .sorted { $0.net.savedAt > $1.net.savedAt }
        return (nearby + rest).map(\.net)
    }

    /// 근처면 뱃지 문구 반환 (아주 가까우면 "여기")
    private func nearbyTag(for network: SavedNetwork) -> String? {
        guard let here = currentNetwork.currentLocation,
              let distance = network.distance(from: here),
              distance <= nearbyRadius else { return nil }
        return distance < 40 ? "📍 여기" : "📍 근처"
    }

    // MARK: - Card container

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
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
                let here = currentNetwork.currentLocation?.coordinate
                store.upsert(ssid: credentials.ssid, password: credentials.password,
                             latitude: here?.latitude, longitude: here?.longitude)
                statusMessage = StatusMessage(text: "'\(credentials.ssid)'에 연결했어요.", isError: false)
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
