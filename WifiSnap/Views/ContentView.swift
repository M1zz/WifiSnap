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
    // '직접 입력'으로 열었는지 — 입력 카드 헤더 문구를 스캔과 구분
    @State private var manualEntry = false
    // 직접 입력 시 SSID 필드에 자동 포커스
    @FocusState private var focusSSID: Bool

    // 시트 상태 (한 뷰에 .sheet를 여러 개 붙이면 충돌하므로 enum 하나로 통합)
    @State private var activeSheet: ActiveSheet?

    // 연결 상태
    @State private var isConnecting = false
    @State private var statusMessage: StatusMessage?

    // 저장된 네트워크 목록 접기 — 기본 접힘. 사용자가 헤더를 탭할 때만 펼친다.
    @State private var savedExpanded = false
    // '와이파이 추가' 섹션 접기 — 연결돼 있으면 접고, 없으면 펼친다.
    @State private var scanExpanded = true
    // 직접 연결 시 SSID 입력 모드: false=목록에서 선택(기본), true=키보드 타이핑
    @State private var typingSSID = false

    enum ActiveSheet: Identifiable {
        case picker(ImagePicker.Source)
        case qr(SavedNetwork)
        case poster(SavedNetwork)
        case map

        var id: String {
            switch self {
            case .picker(let source): return "picker-\(source.id)"
            case .qr(let network): return "qr-\(network.id)"
            case .poster(let network): return "poster-\(network.id)"
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
                scanExpanded = (connectedSaved == nil)
            }
            .onChange(of: connectedSaved?.id) { _, id in
                // 연결되면 '와이파이 추가' 섹션을 접고, 끊기면 다시 펼친다
                withAnimation(.snappy) { scanExpanded = (id == nil) }
            }
            .sheet(item: $activeSheet, content: sheetContent)
            .alert(item: $statusMessage, content: alertContent)
    }

    private var mainStack: some View {
        ScrollView {
            VStack(spacing: 12) {
                connectedCard
                if isRecognizing || hasInput || showScanResult {
                    resultCard
                }
                scanCard
                savedCard
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
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
        case .poster(let network):
            WifiPosterSheet(ssid: network.ssid, password: network.password)
        case .map:
            MapSheet(networks: store.networks)
        }
    }

    private func alertContent(_ message: StatusMessage) -> Alert {
        Alert(title: Text(message.isError ? "연결 실패" : "완료"),
              message: Text(message.text),
              dismissButton: .default(Text("확인")))
    }

    private var hasInput: Bool {
        !credentials.ssid.isEmpty || !credentials.password.isEmpty
    }

    /// 직접 입력 시 SSID 드롭다운 후보 — 지금 연결된 와이파이 + 저장된 네트워크(중복 제거).
    /// iOS는 주변 와이파이 목록을 앱에 제공하지 않아 이 범위가 선택 가능한 최선이다.
    private var selectableSSIDs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        if let current = currentNetwork.currentSSID, !current.isEmpty {
            result.append(current)
            seen.insert(current)
        }
        for network in store.networks where !network.ssid.isEmpty && !seen.contains(network.ssid) {
            result.append(network.ssid)
            seen.insert(network.ssid)
        }
        return result
    }

    /// 직접 연결 시 SSID 입력. 기본은 '목록에서 선택', 후보가 없거나 사용자가 원하면 키보드 입력.
    @ViewBuilder
    private var ssidInput: some View {
        if selectableSSIDs.isEmpty || typingSSID {
            HStack(spacing: 8) {
                TextField("SSID (와이파이 이름)", text: $credentials.ssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .focused($focusSSID)

                // 목록 선택으로 되돌아가기 (선택 가능한 와이파이가 있을 때만)
                if !selectableSSIDs.isEmpty {
                    Button {
                        typingSSID = false
                        focusSSID = false
                    } label: {
                        Image(systemName: "list.bullet.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        } else {
            // 기본: 알고 있는 와이파이(지금 연결됨 + 저장됨)에서 선택
            Menu {
                ForEach(selectableSSIDs, id: \.self) { ssid in
                    Button {
                        credentials.ssid = ssid
                    } label: {
                        Label(ssid, systemImage: ssid == currentNetwork.currentSSID ? "wifi" : "clock.arrow.circlepath")
                    }
                }
                Divider()
                Button {
                    credentials.ssid = ""
                    typingSSID = true
                    focusSSID = true
                } label: {
                    Label("직접 입력…", systemImage: "keyboard")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wifi").foregroundStyle(.secondary)
                    Text(credentials.ssid.isEmpty ? "와이파이 선택" : credentials.ssid)
                        .foregroundStyle(credentials.ssid.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
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

                ConnectedFlipCard(network: network)

                Text("친구에게 QR을 보여주면 바로 연결 · 밀거나 탭하면 안내판 미리보기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                // 카페·매장용: 비치할 예쁜 안내판을 만들어 인쇄/공유
                Button {
                    activeSheet = .poster(network)
                } label: {
                    Label("손님용 안내판 만들기", systemImage: "printer.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.indigo)
            }
        }
    }

    private var scanCard: some View {
        card {
            // 헤더 탭으로 접기/펼치기 (연결돼 있으면 기본 접힘)
            Button {
                withAnimation(.snappy) { scanExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("와이파이 추가").font(.subheadline.weight(.bold))
                        Text("촬영·앨범·직접 연결").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(scanExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if scanExpanded {
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

                // 스캔 없이 SSID를 골라(또는 입력) 비밀번호로 바로 연결
                Button {
                    manualEntry = true
                    credentials = WifiCredentials()
                    typingSSID = selectableSSIDs.isEmpty   // 후보 없으면 바로 타이핑
                    showScanResult = true
                    focusSSID = selectableSSIDs.isEmpty
                } label: {
                    Label("와이파이 선택·직접 연결", systemImage: "keyboard")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var resultCard: some View {
        card {
            cardHeader(icon: manualEntry ? "keyboard" : "camera.viewfinder",
                       title: manualEntry ? "직접 입력으로 연결" : "스캔한 와이파이 연결",
                       subtitle: manualEntry ? "아이디와 비밀번호를 입력해 이 폰을 연결" : "사진에서 읽은 정보로 이 폰을 연결",
                       color: .orange)

            if isRecognizing {
                HStack {
                    ProgressView()
                    Text("인식 중…").foregroundStyle(.secondary)
                }
            } else {
                ssidInput
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
                    // List로 구성해 스와이프 삭제 지원 (칩 디자인은 그대로 유지).
                    // 바깥이 ScrollView이므로 높이를 제한해 내부에서만 스크롤되게 한다.
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
                    .frame(height: min(CGFloat(store.networks.count) * 58 + 8, 360))
                }
            }
        }
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

            // 손님용 안내판 만들기
            Button {
                activeSheet = .poster(network)
            } label: {
                Image(systemName: "printer").rowIcon()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 9))
            .tint(.indigo)

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
        manualEntry = false   // 스캔 경로 — 입력 카드 헤더를 '스캔' 문구로
        typingSSID = true     // 인식한 SSID를 편집 가능한 필드로 보여줌
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

/// 지금 연결된 와이파이 — 앞면은 연결용 QR, 뒷면은 손님용 안내판 미리보기.
/// 카드를 탭하거나 좌우로 밀면 뒤집힌다.
private struct ConnectedFlipCard: View {
    let network: SavedNetwork
    @State private var qrImage: UIImage?
    @State private var posterImage: UIImage?
    @State private var flipped = false

    private let cardHeight: CGFloat = 300

    var body: some View {
        ZStack {
            front.opacity(flipped ? 0 : 1)
            back
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: flipped)
        .contentShape(Rectangle())
        .onTapGesture { flipped.toggle() }
        // ScrollView 세로 스크롤을 막지 않도록 simultaneous, 가로가 우세할 때만 뒤집기
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        flipped.toggle()
                    }
                }
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
                .padding(6)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
        .task(id: network.id) { await generate() }
    }

    private var front: some View {
        Group {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
            } else {
                ProgressView().frame(width: 210, height: 210)
            }
        }
    }

    private var back: some View {
        Group {
            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            } else {
                ProgressView().frame(height: cardHeight)
            }
        }
    }

    /// 앞면 QR과 뒷면 안내판 이미지를 만든다. 안내판은 기본 테마로 렌더한 미리보기.
    @MainActor
    private func generate() async {
        let ssid = network.ssid
        let password = network.password
        let qr = await Task.detached(priority: .userInitiated) {
            QRCodeGenerator.wifiQRImage(ssid: ssid, password: password)
        }.value
        qrImage = qr

        let poster = WifiPosterView(ssid: ssid, password: password,
                                    theme: PosterTheme.all[0],
                                    heading: "무료 와이파이", subtitle: "편하게 이용하세요",
                                    showPassword: true, qrImage: qr)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 3
        posterImage = renderer.uiImage
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
