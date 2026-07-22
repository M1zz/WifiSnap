import SwiftUI
import CoreLocation
import TipKit

struct ContentView: View {
    @StateObject private var store = NetworkStore()
    @StateObject private var currentNetwork = CurrentNetworkService()

    // 기능 안내 팁
    private let scanTip = ScanWifiTip()
    private let nearbyTip = NearbyWifiTip()

    // 스캔 & 편집 상태
    @State private var credentials = WifiCredentials()
    @State private var isRecognizing = false
    // 스캔을 시작하면 인식 실패해도 입력 카드를 열어둬 직접 입력할 수 있게 함
    @State private var showScanResult = false
    // 앱 진입 시 '연결된 와이파이 없음'이면 카메라를 한 번 자동으로 띄운다
    @State private var didAutoPresentCamera = false

    // 시트 상태 (한 뷰에 .sheet를 여러 개 붙이면 충돌하므로 enum 하나로 통합)
    @State private var activeSheet: ActiveSheet?

    // 연결 상태
    @State private var isConnecting = false
    @State private var statusMessage: StatusMessage?

    // 저장된 네트워크 목록 접기 (연결된 와이파이가 있으면 접고, 없으면 펼침)
    @State private var savedExpanded = true

    enum ActiveSheet: Identifiable {
        case picker(ImagePicker.Source)
        case qr(SavedNetwork)
        case map

        var id: String {
            switch self {
            case .picker(let source): return "picker-\(source.id)"
            case .qr(let network): return "qr-\(network.id)"
            case .map: return "map"
            }
        }
    }

    struct StatusMessage: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        mainStack
            .background(backgroundLayer)
            .onAppear {
                currentNetwork.refresh()
                savedExpanded = (connectedSaved == nil)
            }
            .onChange(of: connectedSaved?.id) { _, id in
                // 연결된(로그인 정보 보유) 와이파이가 생기면 목록을 접고, 없으면 펼침
                savedExpanded = (id == nil)
            }
            .onChange(of: currentNetwork.ssidResolved) { _, resolved in
                autoPresentCameraIfNeeded(resolved: resolved)
            }
            .sheet(item: $activeSheet, content: sheetContent)
            .alert(item: $statusMessage, content: alertContent)
    }

    private var mainStack: some View {
        VStack(spacing: 12) {
            connectedCard
            savedCard
            if isRecognizing || hasInput || showScanResult {
                resultCard
            }
            scanCard
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var backgroundLayer: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .picker(let source):
            ImagePicker(source: source) { image in runOCR(on: image) }
                .ignoresSafeArea()
        case .qr(let network):
            QRCodeSheet(ssid: network.ssid, password: network.password)
        case .map:
            MapSheet(networks: store.networks)
        }
    }

    private func alertContent(_ message: StatusMessage) -> Alert {
        Alert(title: Text(message.isError ? "연결 실패" : "완료"),
              message: Text(message.text),
              dismissButton: .default(Text("확인")))
    }

    /// 연결된 와이파이가 없다고 확정되면 카메라를 한 번 자동으로 띄운다.
    /// (연결돼 있으면 그 와이파이가 메인이므로 띄우지 않음)
    private func autoPresentCameraIfNeeded(resolved: Bool) {
        guard resolved, !didAutoPresentCamera else { return }
        didAutoPresentCamera = true
        if currentNetwork.currentSSID == nil,
           activeSheet == nil,
           ImagePicker.isCameraAvailable {
            activeSheet = .picker(.camera)
        }
    }

    private var hasInput: Bool {
        !credentials.ssid.isEmpty || !credentials.password.isEmpty
    }

    /// 지금 연결된 와이파이가 저장돼 있으면 그 네트워크(=여기)
    private var connectedSaved: SavedNetwork? {
        guard let ssid = currentNetwork.currentSSID else { return nil }
        return store.networks.first { $0.ssid == ssid }
    }

    // MARK: - Cards

    /// 지금 연결된(로그인 정보 보유) 와이파이를 크게 보여주는 메인 카드.
    /// 카드 자체가 QR을 표시하므로 별도 '공유하기' 버튼은 없다 — 친구에게 화면만 보여주면 끝.
    @ViewBuilder
    private var connectedCard: some View {
        if let network = connectedSaved {
            card {
                HStack(spacing: 10) {
                    Image(systemName: "wifi")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.green, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("📍 지금 연결됨")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                        Text(network.ssid)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                }

                ConnectedQR(network: network)

                Text("친구에게 이 QR을 보여주면 바로 연결돼요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
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

    /// 위치가 기록된(지도에 찍을 수 있는) 네트워크가 하나라도 있는지
    private var hasMappableNetworks: Bool {
        store.networks.contains { $0.coordinate != nil }
    }

    private var savedCard: some View {
        card {
            // 섹션 헤더 — 제목/개수는 탭하면 접기, 오른쪽에 지도 버튼
            HStack(spacing: 6) {
                Button {
                    withAnimation(.snappy) { savedExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("저장된 네트워크")
                            .font(.subheadline.weight(.semibold))
                        if !store.networks.isEmpty {
                            Text("\(store.networks.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(savedExpanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // 지도에서 보기 (위치가 기록된 네트워크가 있을 때만)
                if hasMappableNetworks {
                    Button {
                        activeSheet = .map
                    } label: {
                        Label("지도", systemImage: "map")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.green)
                }
            }

            if savedExpanded {
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
        }
        .frame(maxHeight: savedExpanded ? .infinity : nil)
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
                    // 긴 이름은 한 줄 가운데 말줄임 처리 (줄바꿈 방지)
                    Text(network.ssid)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let tag = nearbyTag(for: network) {
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                            .fixedSize()          // 뱃지는 압축·줄바꿈 없이 항상 온전히
                            .layoutPriority(1)    // 이름보다 우선 유지 → 이름이 먼저 줄어듦
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        // 인식 결과가 비어도 직접 입력할 수 있도록 입력 카드를 열어둔다
        showScanResult = true
        TextRecognizer.recognizeLines(in: image) { lines in
            credentials = WifiCredentialParser.parse(lines: lines)
            isRecognizing = false
            if credentials.ssid.isEmpty && credentials.password.isEmpty {
                statusMessage = StatusMessage(
                    text: "사진에서 ID/PW를 찾지 못했어요. 직접 입력하거나 더 가까이서 선명하게 찍어보세요.",
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
                // 연결됐으니 입력 카드는 닫고 필드를 비운다
                showScanResult = false
                credentials = WifiCredentials()
                currentNetwork.refresh()
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
                    Image(systemName: "square.and.arrow.up").rowIcon()
                }
                .rowIconButton()
            } else {
                // 생성 전에는 비활성 버튼 모양으로 자리만 유지
                Image(systemName: "square.and.arrow.up")
                    .rowIcon()
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

/// 지금 연결된 와이파이를 큼직한 QR로 표시 — 화면만 보여주면 바로 공유되는 메인 콘텐츠
private struct ConnectedQR: View {
    let network: SavedNetwork
    @State private var qrImage: UIImage?

    var body: some View {
        Group {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
            } else {
                ProgressView()
                    .frame(width: 220, height: 220)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: network.id) {
            let ssid = network.ssid
            let password = network.password
            qrImage = await Task.detached(priority: .userInitiated) {
                QRCodeGenerator.wifiQRImage(ssid: ssid, password: password)
            }.value
        }
    }
}

extension Image {
    /// 저장 목록 행의 작은 정사각형 아이콘 스타일
    func rowIcon() -> some View {
        self.font(.footnote.weight(.bold)).frame(width: 32, height: 32)
    }
}

extension View {
    /// 저장 목록 행의 작은 사각형 버튼 테두리 스타일
    func rowIconButton() -> some View {
        self.buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 9))
            .tint(.blue)
    }

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
