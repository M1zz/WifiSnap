import SwiftUI
import CoreLocation
import TipKit

struct ContentView: View {
    @StateObject private var store = NetworkStore()
    @StateObject private var currentNetwork = CurrentNetworkService()

    // 기능 안내 팁
    private let shareTip = ShareWifiTip()
    private let scanTip = ScanWifiTip()
    private let nearbyTip = NearbyWifiTip()

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
            savedCard
            if isRecognizing || !recognizedLines.isEmpty || hasInput {
                resultCard
            }
            scanCard
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
        )
        .scrollDismissesKeyboard(.interactively)
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
            cardHeader(icon: "arrow.up.circle.fill",
                       title: "내 와이파이 공유",
                       subtitle: "지금 연결된 와이파이를 QR로 전달",
                       color: .green)

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

            PasswordField(placeholder: "비밀번호", text: $sharePassword)

            // 비밀번호 입력란 아래 공유 안내
            TipView(shareTip)

            Button {
                let name = effectiveShareSSID
                // 지금 그 와이파이에 실제로 연결돼 있을 때만 '연결된 장소'로 위치 기록
                let isConnectedHere = currentNetwork.currentSSID == name
                let here = isConnectedHere ? currentNetwork.currentLocation?.coordinate : nil
                store.upsert(ssid: name, password: sharePassword,
                             latitude: here?.latitude, longitude: here?.longitude)
                let network = SavedNetwork(ssid: name, password: sharePassword,
                                           latitude: here?.latitude, longitude: here?.longitude)
                activeSheet = .qr(network)
                // 공유를 경험했으니 팁을 닫고, 다음 안내(스캔·근처)를 열어줌
                shareTip.invalidate(reason: .actionPerformed)
                Task {
                    await WifiSnapTips.usedShare.donate()
                    await WifiSnapTips.savedNetwork.donate()
                }
            } label: {
                Label("QR 만들기", systemImage: "qrcode")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
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
                .popoverTip(scanTip)

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
            cardHeader(icon: "camera.viewfinder",
                       title: "스캔한 와이파이 연결",
                       subtitle: "사진에서 읽은 정보로 이 폰을 연결",
                       color: .orange)

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
                PasswordField(placeholder: "비밀번호", text: $credentials.password)

                Button {
                    connect()
                } label: {
                    if isConnecting {
                        HStack { ProgressView(); Text("연결 중…") }
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("이 폰 연결", systemImage: "wifi")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(credentials.ssid.isEmpty || isConnecting)
            }
        }
        .overlay(alignment: .leading) {
            // 왼쪽 주황색 액센트 바로 공유 카드와 시각적으로 확실히 구분
            RoundedRectangle(cornerRadius: 3)
                .fill(.orange)
                .frame(width: 4)
                .padding(.vertical, 10)
        }
    }

    private var savedCard: some View {
        card {
            // 섹션 헤더
            HStack(spacing: 6) {
                Text("저장된 네트워크")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !store.networks.isEmpty {
                    Text("\(store.networks.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // 근처 추천 안내 (저장된 네트워크가 생기면 노출)
            TipView(nearbyTip)

            if store.networks.isEmpty {
                Text("저장된 네트워크 없음")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                // List로 구성해 스와이프 삭제 지원 (칩 디자인은 그대로 유지)
                List {
                    ForEach(sortedNetworks) { network in
                        savedRow(network)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.delete(ids: [network.id])
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func savedRow(_ network: SavedNetwork) -> some View {
        HStack(spacing: 8) {
            // 탭하면 바로 연결
            Button {
                credentials = WifiCredentials(ssid: network.ssid, password: network.password)
                connect()
            } label: {
                HStack(spacing: 10) {
                    // 와이파이 이름 앞 구분자
                    Image(systemName: "wifi")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(network.ssid).font(.body.weight(.medium))
                    if let tag = nearbyTag(for: network) {
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // QR 바로 보기
            Button {
                activeSheet = .qr(network)
            } label: {
                Image(systemName: "qrcode")
                    .font(.footnote.weight(.bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 9))
            .tint(.blue)

            // QR 이미지 바로 공유
            ShareQRButton(network: network)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
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
        // 지금 연결된 와이파이('여기')는 항상 맨 위로
        let connectedSSID = currentNetwork.currentSSID
        let ordered: [SavedNetwork]
        if let here = currentNetwork.currentLocation {
            let tagged = store.networks.map { (net: $0, dist: $0.distance(from: here)) }
            let nearby = tagged
                .filter { ($0.dist ?? .greatestFiniteMagnitude) <= nearbyRadius }
                .sorted { ($0.dist ?? 0) < ($1.dist ?? 0) }
            let rest = tagged
                .filter { ($0.dist ?? .greatestFiniteMagnitude) > nearbyRadius }
                .sorted { $0.net.savedAt > $1.net.savedAt }
            ordered = (nearby + rest).map(\.net)
        } else {
            ordered = store.networks
        }
        guard let connectedSSID,
              let idx = ordered.firstIndex(where: { $0.ssid == connectedSSID }) else {
            return ordered
        }
        var result = ordered
        result.insert(result.remove(at: idx), at: 0)
        return result
    }

    /// '여기'로 볼 반경(m) — 연결했던 바로 그 지점
    private let hereRadius: CLLocationDistance = 40

    /// 뱃지 문구 반환. 위치 앵커는 '연결 성공 시점'에만 기록되므로,
    /// 그 연결 지점에 다시 왔을 때만 '여기'/'근처'가 뜬다 (단순 추가만 한 건 안 뜸).
    private func nearbyTag(for network: SavedNetwork) -> String? {
        // 지금 이 와이파이에 실제로 연결돼 있으면 확실히 '여기'
        if let current = currentNetwork.currentSSID, current == network.ssid {
            return "📍 여기"
        }
        // 아니면, 연결했던 지점과의 거리로 판단
        guard let here = currentNetwork.currentLocation,
              let distance = network.distance(from: here),
              distance <= nearbyRadius else { return nil }
        return distance <= hereRadius ? "📍 여기" : "📍 근처"
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

    /// 카드 상단 제목 — 아이콘/색으로 카드의 용도를 한눈에 구분
    @ViewBuilder
    private func cardHeader(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.bold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
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
            } else {
                // 스캔한 원본 ID/PW는 저장하되, 위치는 남기지 않는다.
                // '여기'/'근처'는 실제로 연결에 성공한 장소에서만 기록되어야 하기 때문.
                store.upsert(ssid: credentials.ssid, password: credentials.password)
                Task { await WifiSnapTips.savedNetwork.donate() }
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
                Task { await WifiSnapTips.savedNetwork.donate() }
            case .failure(let error):
                statusMessage = StatusMessage(text: error.localizedDescription, isError: true)
            }
        }
    }
}

/// 저장된 네트워크의 QR 이미지를 만들어 시스템 공유 시트로 바로 전달하는 버튼
private struct ShareQRButton: View {
    let network: SavedNetwork
    @State private var qrImage: UIImage?

    var body: some View {
        Group {
            if let qrImage {
                ShareLink(
                    item: Image(uiImage: qrImage),
                    preview: SharePreview("\(network.ssid) 와이파이 QR",
                                          image: Image(uiImage: qrImage))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.footnote.weight(.bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 9))
                .tint(.blue)
            } else {
                // 생성 전에는 비활성 버튼 모양으로 자리만 유지
                Image(systemName: "square.and.arrow.up")
                    .font(.footnote.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.secondary)
                    .opacity(0.5)
            }
        }
        .task(id: network.id) {
            let ssid = network.ssid
            let password = network.password
            qrImage = await Task.detached(priority: .userInitiated) {
                QRCodeGenerator.wifiQRImage(ssid: ssid, password: password)
            }.value
        }
    }
}

extension View {
    /// 현재 편집 중인 텍스트 필드의 키보드를 내린다
    func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
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
