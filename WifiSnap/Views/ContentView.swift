import SwiftUI
import CoreLocation
import TipKit

struct ContentView: View {
    @StateObject private var store = NetworkStore()
    @StateObject private var currentNetwork = CurrentNetworkService()
    /// 사용자가 '설정 > Wi-Fi' 캡처에서 가져온 이름들
    @StateObject private var knownSSIDStore = KnownSSIDStore()
    /// 만들어 둔 손님용 안내판들
    @StateObject private var posterStore = PosterDesignStore()

    // 기능 안내 팁
    private let scanTip = ScanWifiTip()
    private let connectedTip = ConnectedCardTip()
    private let rowActionsTip = SavedRowActionsTip()
    private let nearbyTip = NearbyWifiTip()

    // 스캔 & 편집 상태
    @State private var credentials = WifiCredentials()
    // 사진에서 읽은 SSID 후보들 — 파서의 추측이 틀렸을 때 탭 한 번으로 바꿀 수 있게
    @State private var ssidCandidates: [String] = []
    // 사진에서 읽은 값 조각들 — 아이디·비밀번호 칸으로 끌어다 놓는 퍼즐 조각
    @State private var scanTokens: [String] = []
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
    // 연결이 여러 단계로 길어질 때(표기 바꿔 재시도 등) 버튼에 보여줄 진행 문구
    @State private var connectingNote: String?
    @State private var statusMessage: StatusMessage?

    // 저장된 네트워크 목록 접기 — 기본 접힘. 사용자가 헤더를 탭할 때만 펼친다.
    @State private var savedExpanded = false
    // '와이파이 추가' 섹션 접기 — 연결돼 있으면 접고, 없으면 펼친다.
    @State private var scanExpanded = true
    // 직접 연결 시 SSID 입력 모드: false=목록에서 선택(기본), true=키보드 타이핑
    @State private var typingSSID = false

    // 앱으로 돌아올 때 SSID를 다시 확인 — 위젯이 참조하는 '지금 연결됨'을 최신으로 유지한다
    @Environment(\.scenePhase) private var scenePhase

    enum ActiveSheet: Identifiable {
        case picker(ImagePicker.Source)
        case detail(SavedNetwork)
        case poster(SavedNetwork)
        case share(SavedNetwork, UIImage)
        case map
        case importList

        var id: String {
            switch self {
            case .picker(let source): return "picker-\(source.id)"
            case .detail(let network): return "detail-\(network.id)"
            case .poster(let network): return "poster-\(network.id)"
            case .share(let network, _): return "share-\(network.id)"
            case .map: return "map"
            case .importList: return "importList"
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
                // 이전 버전에서 저장한 네트워크만 있어도 목록 팁이 뜨도록 여기서도 도네이션.
                // (연결 시점에만 도네이션하면 이미 목록이 있는 사용자에게는 팁이 영영 안 뜬다)
                if !store.networks.isEmpty {
                    Task { await WifiSnapTips.savedNetwork.donate() }
                }
            }
            .onChange(of: connectedSaved?.id) { _, id in
                // 연결되면 '와이파이 추가' 섹션을 접고, 끊기면 다시 펼친다
                withAnimation(.snappy) { scanExpanded = (id == nil) }
                anchorConnectedLocation()
            }
            // 위치가 뒤늦게 잡히는 경우(권한 승인 직후 등)에도 앵커를 남긴다
            .onChange(of: currentNetwork.currentLocation?.timestamp) { _, _ in
                anchorConnectedLocation()
            }
            .onChange(of: scenePhase) { _, phase in
                // 설정에서 와이파이를 바꾸고 돌아온 경우를 잡는다
                if phase == .active { currentNetwork.refresh() }
            }
            .sheet(item: $activeSheet, content: sheetContent)
            .alert(item: $statusMessage, content: alertContent)
            .onOpenURL(perform: handleDeepLink)
    }

    /// 위젯 탭 → wifisnap://qr?id=… → 그 위젯에 고정된 와이파이의 QR 상세를 연다.
    /// id가 없거나 이미 지워진 네트워크면 가장 최근 것으로 대체한다.
    /// 잠금화면 위젯은 QR이 vibrant 렌더링으로 변환돼 스캔이 어려우므로 이 경로가 실질적인 사용법이다.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "wifisnap", url.host == "qr" else { return }

        let requestedID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "id" }?.value
        let pinned = requestedID.flatMap { id in
            store.networks.first { $0.id.uuidString == id }
        }
        guard let network = pinned ?? store.networks.max(by: { $0.savedAt < $1.savedAt }) else { return }
        activeSheet = .detail(network)
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
        case .detail(let network):
            NetworkDetailSheet(network: network, posterStore: posterStore) {
                credentials = WifiCredentials(ssid: network.ssid, password: network.password)
                connect()
            }
        case .poster(let network):
            PosterListSheet(store: posterStore, ssid: network.ssid, password: network.password)
        case .share(let network, let image):
            ActivityShareSheet(image: image)
                .ignoresSafeArea()
                .presentationDetents([.medium, .large])
                .id(network.id)
        case .map:
            MapSheet(networks: store.networks)
        case .importList:
            WifiListImportSheet(store: knownSSIDStore)
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

    /// 선택 가능한 와이파이 한 줄
    private struct SSIDOption: Identifiable {
        let ssid: String
        let icon: String
        let detail: String?
        var id: String { ssid }
    }

    /// 이 폰이 '아는' 와이파이 — 지금 연결됨 + 앱에 저장됨(근처순) + 앱이 설정해 둠.
    /// iOS는 주변 와이파이 스캔을 앱에 허용하지 않으므로(NEHotspotHelper 특별 엔타이틀먼트 전용),
    /// 이 셋을 합친 것이 목록으로 제공할 수 있는 최대 범위다.
    private var knownOptions: [SSIDOption] {
        var seen = Set<String>()
        var result: [SSIDOption] = []
        func add(_ ssid: String, icon: String, detail: String?) {
            let name = ssid.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name).inserted else { return }
            result.append(SSIDOption(ssid: name, icon: icon, detail: detail))
        }
        if let current = currentNetwork.currentSSID {
            add(current, icon: "wifi", detail: "지금 연결됨")
        }
        for network in sortedNetworks {
            add(network.ssid, icon: "clock.arrow.circlepath", detail: nearbyTag(for: network))
        }
        for ssid in currentNetwork.configuredSSIDs {
            add(ssid, icon: "gearshape", detail: "이 폰에 설정됨")
        }
        // 사용자가 '설정 > Wi-Fi' 캡처로 알려준 이름들
        for ssid in knownSSIDStore.ssids {
            add(ssid, icon: "text.viewfinder", detail: "캡처에서 가져옴")
        }
        return result
    }

    private var knownSSIDs: [String] { knownOptions.map(\.ssid) }

    /// SSID 입력. 기본은 '목록/후보에서 선택', 사용자가 원하면 키보드 입력.
    /// 고를 게 하나도 없어도 메뉴를 띄운다 — 거기에 '캡처에서 가져오기' 진입점이 있기 때문.
    @ViewBuilder
    private var ssidInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typingSSID {
                HStack(spacing: 8) {
                    TextField("SSID (와이파이 이름)", text: $credentials.ssid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .focused($focusSSID)

                    // 목록 선택으로 되돌아가기
                    Button {
                        typingSSID = false
                        focusSSID = false
                    } label: {
                        Image(systemName: "list.bullet.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                ssidMenu
            }

            // 사진에서 읽은 후보들 — 파서가 엉뚱한 줄을 골랐을 때 탭 한 번으로 교정
            if !ssidCandidates.isEmpty && !typingSSID {
                ssidCandidateChips
            }
        }
    }

    private var ssidMenu: some View {
        Menu {
            if !ssidCandidates.isEmpty {
                Section("사진에서 읽음") {
                    ForEach(ssidCandidates, id: \.self) { candidate in
                        Button { selectSSID(candidate) } label: {
                            Label(candidate, systemImage: "camera.viewfinder")
                        }
                    }
                }
            }
            if !knownOptions.isEmpty {
                Section("이 폰이 아는 와이파이") {
                    ForEach(knownOptions) { option in
                        Button { selectSSID(option.ssid) } label: {
                            Label(option.detail.map { "\(option.ssid) · \($0)" } ?? option.ssid,
                                  systemImage: option.icon)
                        }
                    }
                }
            }
            Divider()
            // iOS가 저장된 와이파이 목록을 안 주므로, 사용자가 설정 화면을 캡처해 알려주는 경로
            Button {
                activeSheet = .importList
            } label: {
                Label("설정 캡처에서 목록 가져오기…", systemImage: "text.viewfinder")
            }
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

    private var ssidCandidateChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("사진에서 읽은 이름 — 맞는 걸 골라주세요")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ssidCandidates, id: \.self) { candidate in
                        let isSelected = candidate == credentials.ssid
                        Button {
                            selectSSID(candidate)
                        } label: {
                            Text(candidate)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.orange.opacity(0.2) : Color(.tertiarySystemFill),
                                            in: Capsule())
                                .foregroundStyle(isSelected ? .orange : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)   // 캡슐 테두리가 잘리지 않게
            }
        }
    }

    /// 후보를 고를 때, 이 폰이 아는 이름과 사실상 같으면 그 이름으로 교정한다.
    /// (OCR이 O↔0, l↔1 등을 헷갈려 실제로 없는 이름을 만들어내는 걸 막는다)
    private func selectSSID(_ ssid: String) {
        credentials.ssid = SSIDMatcher.bestMatch(for: ssid, in: knownSSIDs) ?? ssid
        typingSSID = false
        focusSSID = false
    }

    /// 지금 연결된 와이파이가 저장돼 있으면 그 네트워크(=여기).
    /// 미리 만들어 둔 이름과 iOS가 알려준 표기가 대소문자만 달라도 같은 것으로 본다.
    private var connectedSaved: SavedNetwork? {
        guard let ssid = currentNetwork.currentSSID else { return nil }
        return store.network(for: ssid)
    }

    /// 이 네트워크에 지금 연결돼 있는지
    private func isConnected(_ network: SavedNetwork) -> Bool {
        guard let current = currentNetwork.currentSSID else { return false }
        return SavedNetwork.matchKey(current) == network.matchKey
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

                ConnectedFlipCard(network: network, design: posterStore.current) {
                    // 카드를 뒤집어 봤으면 사용법을 익힌 것 — 팁을 거둔다
                    connectedTip.invalidate(reason: .actionPerformed)
                }

                TipView(connectedTip)

                // 카페·매장용: 비치할 안내판을 여러 장 만들어 인쇄/공유.
                // 가장 최근에 고친 안내판이 위 카드 뒷면에 보인다.
                Button {
                    activeSheet = .poster(network)
                } label: {
                    Label("내 안내판 (\(posterStore.designs.count))", systemImage: "doc.text.image")
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
                        Text("촬영·앨범·직접 입력").font(.caption).foregroundStyle(.secondary)
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

                // 스캔 없이 아이디·비밀번호를 손으로 쳐서 연결하거나, 연결 없이 QR만 만든다.
                // 목록에서 고르는 건 실제로 쓸모가 없었으므로 바로 키보드를 띄운다.
                Button {
                    manualEntry = true
                    credentials = WifiCredentials()
                    ssidCandidates = []    // 스캔 후보는 직접 입력 모드와 무관
                    scanTokens = []
                    typingSSID = true
                    showScanResult = true
                    focusSSID = true
                } label: {
                    Label("아이디·비밀번호 직접 입력 (QR 만들기)", systemImage: "keyboard")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var resultCard: some View {
        card {
            cardHeader(icon: manualEntry ? "keyboard" : "camera.viewfinder",
                       title: manualEntry ? "직접 입력한 와이파이" : "스캔한 와이파이",
                       subtitle: "이 폰을 연결하거나, 연결 없이 QR만 만들어요",
                       color: .orange)

            if isRecognizing {
                HStack {
                    ProgressView()
                    Text("인식 중…").foregroundStyle(.secondary)
                }
            } else {
                if scanTokens.isEmpty {
                    ssidInput
                    PasswordField(placeholder: "비밀번호", text: $credentials.password)
                } else {
                    // 사진에서 읽은 게 있으면 조각을 끌어다 놓아 고치는 퍼즐로 편집한다
                    CredentialPuzzleView(groups: puzzleGroups,
                                         ssid: $credentials.ssid,
                                         password: $credentials.password)
                }

                Button {
                    connect()
                } label: {
                    if isConnecting {
                        HStack { ProgressView(); Text(connectingNote ?? "연결 중…") }
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

                // 연결은 하지 않고 QR만 — 아직 그 자리에 없는 와이파이(다른 집·매장·예약한 숙소)도
                // 이름·비밀번호만 알면 미리 만들어 둘 수 있어야 한다.
                Button {
                    saveWithoutConnecting()
                } label: {
                    Label("연결 없이 QR 만들기", systemImage: "qrcode")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.blue)
                .disabled(credentials.ssid.isEmpty || isConnecting)

                Text("이 폰을 연결하지 않고 저장만 해요. 비밀번호가 틀리면 QR도 연결되지 않으니 확인해 주세요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    /// 퍼즐에 올릴 조각 묶음 — 사진에서 읽은 값 + 이 폰이 아는 이름.
    /// 사진 인식이 통째로 틀렸을 때도 아는 이름을 끌어다 놓으면 되도록 함께 얹는다.
    private var puzzleGroups: [CredentialPuzzleView.TokenGroup] {
        [
            .init(id: "photo", title: "사진에서 읽음", icon: "camera.viewfinder", tokens: scanTokens),
            .init(id: "known", title: "이 폰이 아는 이름", icon: "wifi", tokens: knownSSIDs)
        ].filter { !$0.tokens.isEmpty }
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
                // 목록 조작법(탭·스와이프) → 써 보고 나면 근처 추천 안내로 넘어간다
                TipView(rowActionsTip)
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
                                // 왼쪽으로 밀면 → QR 공유
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        shareQR(network)
                                    } label: {
                                        Label("공유", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.blue)
                                }
                                // 오른쪽으로 밀면 → 이 폰 연결
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        connect(network)
                                    } label: {
                                        Label("연결", systemImage: "wifi")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: savedListHeight)
                }
            }
        }
    }

    /// 저장 목록 행 — 이름을 온전히 보여주는 것이 최우선이라 행에는 이름만 두고,
    /// 공유/연결은 스와이프, 나머지 기능은 탭 → 상세 화면으로 옮겼다.
    @ViewBuilder
    private func savedRow(_ network: SavedNetwork) -> some View {
        Button {
            markSavedRowUsed()
            activeSheet = .detail(network)
        } label: {
            HStack(spacing: 10) {
                // 와이파이 이름 앞 구분자
                Image(systemName: "wifi")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.blue)

                // 이름은 어떤 길이여도 잘리지 않는다 — 모자라면 여러 줄로 감싼다
                Text(network.ssid)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let tag = nearbyTag(for: network) {
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                        .fixedSize()   // 뱃지는 압축·줄바꿈 없이 항상 온전히
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button {
                activeSheet = .poster(network)
            } label: {
                Label("안내판 만들기", systemImage: "printer")
            }
            Button(role: .destructive) {
                store.delete(ids: [network.id])
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    /// 목록 높이 — 바깥이 ScrollView라 List에 명시적 높이가 필요하다.
    /// 이름이 길어 줄바꿈되는 행이 있으므로 글자 폭으로 줄 수를 어림한다. 넘치면 목록 안에서 스크롤.
    private var savedListHeight: CGFloat {
        let nameWidth: CGFloat = 250   // 아이콘·뱃지·화살표를 뺀 이름 영역의 대략적인 폭(pt)
        let total = sortedNetworks.reduce(CGFloat(8)) { sum, network in
            // 한글·CJK 한 글자는 라틴 문자의 약 두 배 폭을 차지한다
            let width = network.ssid.reduce(CGFloat(0)) { $0 + ($1.isASCII ? 9.5 : 17) }
            let lines = max(1, Int((width / nameWidth).rounded(.up)))
            return sum + 32 + CGFloat(lines) * 21   // 32 = 상하 여백(24) + 행 간격(8)
        }
        return min(total, 360)
    }

    /// 스와이프 공유 — 스와이프 액션 안에서는 ShareLink가 제대로 동작하지 않아
    /// QR을 만들어 시스템 공유 시트를 직접 띄운다.
    private func shareQR(_ network: SavedNetwork) {
        guard let image = QRCodeGenerator.wifiQRImage(ssid: network.ssid,
                                                      password: network.password) else {
            statusMessage = StatusMessage(text: "QR을 만들지 못했어요.", isError: true)
            return
        }
        markSavedRowUsed()
        activeSheet = .share(network, image)
    }

    /// 저장된 네트워크로 바로 연결
    private func connect(_ network: SavedNetwork) {
        markSavedRowUsed()
        credentials = WifiCredentials(ssid: network.ssid, password: network.password)
        connect()
    }

    /// 목록 행을 한 번이라도 써 봤음 — 조작법 팁을 거두고 다음 팁(근처 추천)을 열어준다
    private func markSavedRowUsed() {
        rowActionsTip.invalidate(reason: .actionPerformed)
        Task { await WifiSnapTips.usedSavedRow.donate() }
    }

    // MARK: - Location helpers

    /// 근처로 볼 반경(m)
    private let nearbyRadius: CLLocationDistance = 150

    /// 현재 위치 기준: 반경 안의 네트워크를 거리순으로 맨 위에, 나머지는 최근 저장순
    private var sortedNetworks: [SavedNetwork] {
        // 지금 연결된 와이파이('여기')는 항상 맨 위로
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
        guard let idx = ordered.firstIndex(where: { isConnected($0) }) else {
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
        if isConnected(network) { return "📍 여기" }
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
        typingSSID = false    // 인식 결과는 후보 중에서 고르는 게 기본
        // 인식 결과가 비어도 직접 입력할 수 있도록 입력 카드를 열어둔다
        showScanResult = true
        TextRecognizer.recognizeLines(in: image) { lines in
            let scan = WifiCredentialParser.parse(lines: lines)
            credentials = scan.credentials
            // OCR 오탈자 교정: 아는 이름과 사실상 같으면 그 이름으로 바꾼다 (후보도 같이 교정해야
            // 칩의 선택 표시가 어긋나지 않는다)
            let known = knownSSIDs
            var seen = Set<String>()
            ssidCandidates = scan.ssidCandidates
                .map { SSIDMatcher.bestMatch(for: $0, in: known) ?? $0 }
                .filter { seen.insert($0).inserted }
            // 퍼즐 조각은 사진에 나온 순서 그대로 (아는 이름으로의 교정만 적용)
            var seenTokens = Set<String>()
            scanTokens = scan.tokens
                .map { SSIDMatcher.bestMatch(for: $0, in: known) ?? $0 }
                .filter { seenTokens.insert($0).inserted }
            if let corrected = SSIDMatcher.bestMatch(for: credentials.ssid, in: known) {
                credentials.ssid = corrected
            }
            isRecognizing = false
            // 인식 결과는 저장하지 않는다 — 잘못 읽은 이름이 목록에 쌓이는 걸 막기 위해
            // 실제 연결에 성공한 뒤에만 저장한다(connect 참고).
            if credentials.ssid.isEmpty && credentials.password.isEmpty {
                statusMessage = StatusMessage(
                    text: "사진에서 ID/PW를 찾지 못했어요. 직접 입력하거나 더 가까이서 선명하게 찍어보세요.",
                    isError: true
                )
            }
        }
    }

    /// 지금 연결된 와이파이가 저장돼 있는데 위치가 비어 있으면 현재 위치를 앵커로 남긴다.
    /// 연결 없이 QR만 만들어 둔 것, 설정에서 직접 붙은 것도 이 경로로 '📍 여기/근처'를 갖게 된다.
    private func anchorConnectedLocation() {
        guard let ssid = currentNetwork.currentSSID,
              let here = currentNetwork.currentLocation else { return }
        store.anchorLocationIfMissing(ssid: ssid, at: here)
    }

    /// 연결하지 않고 입력한 이름·비밀번호만 저장하고, 바로 QR 상세를 연다.
    /// iOS는 '연결에 성공해야만' 와이파이 정보를 얻을 수 있게 하지만, QR을 만드는 데는
    /// 연결이 필요 없다 — 알고 있는 정보만으로 미리 만들어 둘 수 있어야 한다.
    private func saveWithoutConnecting() {
        // 붙여넣기·OCR로 섞여 들어온 제로폭 문자, 전각 영숫자를 걷어낸다.
        // 눈에는 똑같아 보여도 그대로 QR에 넣으면 스캔한 폰이 조용히 연결에 실패한다.
        let ssid = SSIDMatcher.sanitize(credentials.ssid)
        guard !ssid.isEmpty else { return }
        let password = credentials.password
        dismissKeyboard()

        // 위치는 여기서 기록하지 않는다 — 아직 그 자리에 가 있지 않을 수 있다(다른 집·예약한 숙소).
        // 나중에 실제로 그 와이파이에 연결되면 anchorConnectedLocation()이 그때의 위치를 남긴다.
        store.upsert(ssid: ssid, password: password)

        // 입력 카드는 닫고 필드를 비운다 (연결 성공 시와 동일한 정리)
        showScanResult = false
        credentials = WifiCredentials()
        ssidCandidates = []
        scanTokens = []
        Task { await WifiSnapTips.savedNetwork.donate() }

        guard let saved = store.network(for: ssid) else { return }
        activeSheet = .detail(saved)
    }

    private func connect() {
        guard !credentials.ssid.isEmpty else { return }
        isConnecting = true
        connectingNote = nil
        let password = credentials.password
        WifiConnector.connect(ssid: credentials.ssid,
                              password: password,
                              // 붙었는지 이름으로 확인하려면 SSID 조회 권한이 필요하다
                              canReadSSID: currentNetwork.canReadSSID,
                              onProgress: { note in connectingNote = note }) { result in
            isConnecting = false
            connectingNote = nil
            switch result {
            case .success(let joined):
                // iOS가 알려준 표기를 저장한다 — OCR이 대소문자를 틀렸어도, 연결 전에 미리
                // 만들어 둔 QR의 이름이 달랐어도 여기서 그 항목의 이름이 정식 표기로 바로잡힌다.
                let here = currentNetwork.currentLocation?.coordinate
                store.upsert(ssid: joined.ssid, password: password,
                             latitude: here?.latitude, longitude: here?.longitude,
                             verifiedName: true)
                statusMessage = StatusMessage(
                    text: joined.verified
                        ? "'\(joined.ssid)'에 연결했어요."
                        : "'\(joined.ssid)' 연결을 설정했어요.\n연결됐는지 확인하려면 위치 권한이 필요해요. (설정 > WifiSnap > 위치)",
                    isError: false
                )
                // 연결됐으니 입력 카드는 닫고 필드를 비운다
                showScanResult = false
                credentials = WifiCredentials()
                ssidCandidates = []
                scanTokens = []
                currentNetwork.refresh()
                Task { await WifiSnapTips.savedNetwork.donate() }
            case .failure(let error):
                statusMessage = StatusMessage(text: error.localizedDescription, isError: true)
            }
        }
    }
}

/// 지금 연결된 와이파이 — 앞면은 연결용 QR, 뒷면은 손님용 안내판 미리보기.
/// 카드를 탭하거나 좌우로 밀면 뒤집힌다.
private struct ConnectedFlipCard: View {
    let network: SavedNetwork
    /// 뒷면에 보여줄 안내판 — 가장 최근에 고친 것
    let design: PosterDesign
    /// 카드를 처음 뒤집었을 때 — 사용법 팁을 거두는 데 쓴다
    var onFlip: () -> Void = {}

    @State private var qrImage: UIImage?
    @State private var posterImage: UIImage?
    @State private var flipped = false
    /// 카드 실제 폭 — 뒷면 안내판을 축소 없이 보여주려면 필요하다
    @State private var cardWidth: CGFloat = 330

    /// 앞면(QR) 높이
    private let frontHeight: CGFloat = 340

    /// 뒷면 높이 — 안내판 원본 비율 그대로 잡는다.
    /// 예전처럼 고정 높이에 밀어 넣으면 절반 크기로 축소돼 글자가 작아 보였다.
    private var backHeight: CGFloat {
        guard let posterImage, posterImage.size.width > 0 else { return frontHeight }
        return cardWidth * posterImage.size.height / posterImage.size.width
    }

    /// 안내판 내용이 바뀌면 다시 렌더한다 (updatedAt이 편집 때마다 갱신됨)
    private var renderKey: String {
        "\(network.id)|\(design.id)|\(design.updatedAt.timeIntervalSince1970)"
    }

    var body: some View {
        ZStack {
            front.opacity(flipped ? 0 : 1)
            back
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(maxWidth: .infinity)
        .frame(height: flipped ? backHeight : frontHeight)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { cardWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in cardWidth = width }
            }
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: flipped)
        .contentShape(Rectangle())
        .onTapGesture { flip() }
        // ScrollView 세로 스크롤을 막지 않도록 simultaneous, 가로가 우세할 때만 뒤집기
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        flip()
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
        .task(id: renderKey) { await generate() }
    }

    private func flip() {
        flipped.toggle()
        onFlip()
    }

    private var front: some View {
        Group {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 264, height: 264)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ProgressView().frame(width: 264, height: 264)
            }
        }
    }

    /// 뒷면 — 안내판을 카드 폭에 꽉 채워 원본 크기로 보여준다
    private var back: some View {
        Group {
            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 앞면 QR과 뒷면 안내판 이미지를 만든다. 안내판은 저장된 문구·테마로 렌더한다.
    @MainActor
    private func generate() async {
        let ssid = network.ssid
        let password = network.password
        let qr = await Task.detached(priority: .userInitiated) {
            QRCodeGenerator.wifiQRImage(ssid: ssid, password: password)
        }.value
        qrImage = qr

        // 미리보기는 항상 카드 형태로 (A4로 만든 안내판도 카드 뒷면에는 카드로 보여준다)
        var cardDesign = design
        cardDesign.layoutID = PosterLayout.card.rawValue
        let poster = WifiPosterView(ssid: ssid, password: password,
                                    design: cardDesign, qrImage: qr)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 3
        posterImage = renderer.uiImage
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
