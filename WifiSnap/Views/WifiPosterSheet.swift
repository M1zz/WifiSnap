import SwiftUI
import UIKit
import PhotosUI

// MARK: - 안내판 만들기 시트

/// 안내판 한 장을 편집하는 시트. 고칠 때마다 저장소에 바로 저장된다.
/// 인쇄되는 글자는 라벨까지 전부 여기서 바꿔 쓸 수 있다.
struct WifiPosterSheet: View {
    let ssid: String
    let password: String
    @ObservedObject var store: PosterDesignStore
    /// 편집 대상. 화면 안에서 고치고, 바뀔 때마다 store에 저장한다.
    @State var design: PosterDesign

    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale

    @State private var qrImage: UIImage?
    @State private var shareItem: ShareImage?
    // 로고는 사진이라 저장하지 않고 이 화면에서만 유지한다
    @State private var logoImage: UIImage?
    @State private var logoPickerItem: PhotosPickerItem?
    // 테마 · A4 · 가게 이름 · 덧붙일 문구 · 라벨은 Plus. 잠긴 것을 고르면 페이월을 낸다.
    // 이미 고른 값은 그대로 그리고 인쇄한다 — 잠그는 것은 새로 고르는 것뿐이다.
    @ObservedObject private var purchases = PurchaseManager.shared
    @State private var paywall: ProFeature?

    private var theme: PosterTheme { design.theme }
    private var layout: PosterLayout { design.layout }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    poster
                        .padding(.top, 8)

                    layoutPicker
                    themeStrip
                    controls
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(design.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportPoster()
                    } label: {
                        Label("공유", systemImage: "square.and.arrow.up")
                    }
                    .disabled(qrImage == nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                shareButton
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(image: item.image)
        }
        .sheet(item: $paywall) { PaywallView(highlight: $0) }
        // 고칠 때마다 바로 저장 — '저장' 버튼을 눌러야 하는 부담을 없앤다
        .onChange(of: design) { _, updated in
            store.save(updated)
        }
        .onChange(of: logoPickerItem) { _, item in
            Task { await loadLogo(from: item) }
        }
        .task {
            let ssid = self.ssid
            let password = self.password
            qrImage = await Task.detached(priority: .userInitiated) {
                QRCodeGenerator.wifiQRImage(ssid: ssid, password: password)
            }.value
        }
    }

    /// 미리보기용 폭(이보다 넓은 A4는 축소해서 보여준다)
    private let previewWidth: CGFloat = 340

    private var poster: some View {
        let m = layout.metrics
        let scale = min(1, previewWidth / m.width)
        // scaleEffect는 레이아웃 크기를 바꾸지 않으므로, 바깥 frame으로 축소된 실제 크기만큼만 자리를 차지하게 한다.
        return posterView
            .scaleEffect(scale)
            .frame(width: m.width * scale,
                   height: scale < 1 ? (m.height ?? 0) * scale : nil)
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    /// 미리보기와 내보내기가 공유하는 실제 안내판 뷰
    private var posterView: WifiPosterView {
        WifiPosterView(ssid: ssid, password: password, design: design,
                       qrImage: qrImage, logoImage: logoImage)
    }

    // MARK: 레이아웃(카드 / A4) 선택

    private var layoutPicker: some View {
        // A4 는 Plus — 잠겨 있으면 고르는 대신 페이월을 낸다.
        let layout = Binding<String>(
            get: { design.layoutID },
            set: { id in
                if id == PosterLayout.a4.rawValue, !purchases.allows(.a4Poster) {
                    paywall = .a4Poster
                } else {
                    withAnimation(.snappy) { design.layoutID = id }
                }
            })
        return Picker("형태", selection: layout) {
            ForEach(PosterLayout.allCases) { option in
                Text(option.label).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: 테마 선택 스트립

    private var themeStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("디자인")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PosterTheme.all) { item in
                        let isSelected = design.themeID == item.id
                        let isLocked = !FreeLimit.themeIDs.contains(item.id) && !purchases.allows(.allThemes)
                        Button {
                            if isLocked {
                                paywall = .allThemes
                            } else {
                                withAnimation(.snappy) { design.themeID = item.id }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(item.gradient)
                                    .frame(width: 52, height: 52)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        if isLocked {
                                            Image(systemName: "lock.fill")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(4)
                                                .background(.black.opacity(0.55), in: Circle())
                                                .padding(3)
                                        }
                                    }
                                Text(item.name)
                                    .font(.caption2.weight(isSelected ? .bold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityHint(isLocked ? ProLockBadge.spoken(.allThemes) : "")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: 문구·옵션

    private var controls: some View {
        VStack(spacing: 14) {
            labeledField(title: String(localized: "안내판 이름 (목록에서만 보임)"), text: $design.name,
                         placeholder: String(localized: "예) 계산대용"))

            Divider()
            logoRow

            Divider()
            Text("안내판에 인쇄되는 글자")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            labeledField(title: String(localized: "매장 이름"), text: $design.storeName, placeholder: String(localized: "예) 라운지 카페"),
                         lockedBy: .signText)
            labeledField(title: String(localized: "뱃지 (비우면 숨김)"), text: $design.badge, placeholder: "WiFi")
            labeledField(title: String(localized: "제목"), text: $design.heading, placeholder: String(localized: "무료 와이파이"))
            labeledField(title: String(localized: "안내 문구"), text: $design.subtitle, placeholder: String(localized: "편하게 이용하세요"))
            labeledField(title: String(localized: "네트워크 라벨"), text: $design.networkLabel, placeholder: String(localized: "네트워크"),
                         lockedBy: .signText)
            labeledField(title: String(localized: "비밀번호 라벨"), text: $design.passwordLabel, placeholder: String(localized: "비밀번호"),
                         lockedBy: .signText)
            labeledField(title: String(localized: "맨 아래 문구 (비우면 숨김)"), text: $design.footer,
                         placeholder: String(localized: "카메라로 QR을 비추면 자동 연결"))

            Divider()
            extraLinesEditor

            Divider()
            Toggle(isOn: $design.showPassword) {
                Label("비밀번호 표시", systemImage: "key.fill")
                    .font(.subheadline)
            }
            .padding(.vertical, 4)

            HStack {
                Text("고치는 즉시 저장돼요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("글자 되돌리기") {
                    withAnimation(.snappy) { resetText() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    /// 매장 로고 선택/미리보기/제거
    private var logoRow: some View {
        HStack(spacing: 12) {
            Group {
                if let logoImage {
                    Image(uiImage: logoImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "storefront")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.tertiarySystemFill))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 1) {
                Text("매장 로고")
                    .font(.subheadline.weight(.semibold))
                Text(logoImage == nil ? String(localized: "선택 사항 — 상단에 표시") : String(localized: "적용됨"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if logoImage != nil {
                Button("제거") {
                    logoImage = nil
                    logoPickerItem = nil
                }
                .font(.subheadline)
                .tint(.red)
            }

            PhotosPicker(selection: $logoPickerItem, matching: .images) {
                Text(logoImage == nil ? String(localized: "선택") : String(localized: "변경"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    /// 선택한 사진을 로고 이미지로 로드
    private func loadLogo(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        logoImage = image
    }

    /// 영업시간·인스타 계정처럼 매장이 원하는 만큼 덧붙이는 줄.
    /// Plus 가 없으면 이미 쓴 줄은 보이고 지울 수 있지만, 새로 더하거나 고치지는 못한다.
    private var extraLinesEditor: some View {
        let isLocked = !purchases.allows(.signText)
        return VStack(alignment: .leading, spacing: 8) {
            Text("직접 쓰는 줄")
                .font(.subheadline.weight(.semibold))
            Text("영업시간, 인스타 계정, 매장 안내처럼 원하는 문구를 줄 단위로 넣으세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(design.extraLines.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    if isLocked {
                        Text(design.extraLines[index])
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("예) 영업시간 09:00–22:00", text: $design.extraLines[index])
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        design.extraLines.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("이 줄 삭제")
                }
            }

            Button {
                if isLocked { paywall = .signText } else { design.extraLines.append("") }
            } label: {
                Label("줄 추가", systemImage: isLocked ? "lock.fill" : "plus.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 인쇄되는 글자만 기본값으로 되돌린다 (테마·형태·안내판 이름은 그대로)
    private func resetText() {
        let defaults = PosterDesign()
        design.storeName = defaults.storeName
        design.badge = defaults.badge
        design.heading = defaults.heading
        design.subtitle = defaults.subtitle
        design.networkLabel = defaults.networkLabel
        design.passwordLabel = defaults.passwordLabel
        design.footer = defaults.footer
        design.extraLines = []
    }

    /// - Parameter lockedBy: 이 칸을 여는 기능. 잠겨 있으면 지금 값만 보이고, 누르면 페이월이 뜬다.
    private func labeledField(title: String, text: Binding<String>, placeholder: String,
                              lockedBy feature: ProFeature? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let feature, !purchases.allows(feature) {
                Button {
                    paywall = feature
                } label: {
                    HStack(spacing: 8) {
                        Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                            .foregroundStyle(text.wrappedValue.isEmpty ? .tertiary : .secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        ProLockBadge(feature: feature)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(text.wrappedValue)
                .accessibilityHint(ProLockBadge.spoken(feature))
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var shareButton: some View {
        Button {
            exportPoster()
        } label: {
            Label("안내판 이미지 공유·인쇄", systemImage: "printer.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.borderedProminent)
        .disabled(qrImage == nil)
        .padding(16)
        .background(.bar)
    }

    // MARK: 내보내기

    /// 현재 안내판을 고해상도 이미지로 렌더링해 시스템 공유 시트(인쇄 포함)로 전달.
    @MainActor
    private func exportPoster() {
        // 렌더러는 화면의 환경을 물려받지 않는다 — 아랍어 안내판도 오른쪽에서 왼쪽으로 그리게 넘겨 준다
        let renderer = ImageRenderer(content: posterView
            .environment(\.layoutDirection, layoutDirection)
            .environment(\.locale, locale))
        // 레이아웃별 배율 — 카드 3배(약 1020px), A4 6배(약 2160×3054px, 인쇄용)
        renderer.scale = layout.metrics.exportScale
        if let image = renderer.uiImage {
            shareItem = ShareImage(image: image)
        }
    }
}

/// 공유 시트에 전달할 이미지 래퍼 (sheet(item:)용 Identifiable)
private struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

#Preview {
    WifiPosterSheet(ssid: "CAFE_WIFI_2G", password: "welcome1234",
                    store: PosterDesignStore(), design: PosterDesign(name: "미리보기"))
}
