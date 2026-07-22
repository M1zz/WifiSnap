import SwiftUI
import UIKit
import PhotosUI

// MARK: - 테마

/// 안내판 디자인 테마. 배경 그라데이션 + 글자색 조합만 바뀌고,
/// QR은 스캔 안정성을 위해 항상 흰 배경 위 검정으로 고정한다.
struct PosterTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let colors: [Color]     // 배경 그라데이션 (좌상 → 우하)
    let foreground: Color   // 제목·본문 글자색
    let secondary: Color    // 라벨·부제 글자색
    let badge: Color        // 상단 뱃지 강조색

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 정보 카드(반투명 패널) 배경. 밝은 테마에선 진하게, 어두운 테마에선 밝게.
    var panel: Color { foreground.opacity(0.10) }

    static let all: [PosterTheme] = [
        PosterTheme(id: "midnight", name: "미드나잇",
                    colors: [Color(hex: 0x1E1B4B), Color(hex: 0x4338CA), Color(hex: 0x7C3AED)],
                    foreground: .white, secondary: Color(hex: 0xC7D2FE), badge: Color(hex: 0x34D399)),
        PosterTheme(id: "sunset", name: "선셋",
                    colors: [Color(hex: 0xFF6B6B), Color(hex: 0xFF8E53), Color(hex: 0xFFB088)],
                    foreground: .white, secondary: Color(hex: 0xFFF1E6), badge: .white),
        PosterTheme(id: "mint", name: "민트",
                    colors: [Color(hex: 0x06B6D4), Color(hex: 0x10B981)],
                    foreground: .white, secondary: Color(hex: 0xE0F7F4), badge: .white),
        PosterTheme(id: "ocean", name: "오션",
                    colors: [Color(hex: 0x2563EB), Color(hex: 0x0EA5E9), Color(hex: 0x22D3EE)],
                    foreground: .white, secondary: Color(hex: 0xDBEAFE), badge: .white),
        PosterTheme(id: "forest", name: "포레스트",
                    colors: [Color(hex: 0x065F46), Color(hex: 0x059669), Color(hex: 0x34D399)],
                    foreground: .white, secondary: Color(hex: 0xD1FAE5), badge: .white),
        PosterTheme(id: "cafe", name: "카페",
                    colors: [Color(hex: 0xF5E9DA), Color(hex: 0xE8D3B5)],
                    foreground: Color(hex: 0x5B3A29), secondary: Color(hex: 0x8A6E56), badge: Color(hex: 0xB5835A)),
        PosterTheme(id: "mono", name: "모노",
                    colors: [Color(hex: 0xFAFAFA), Color(hex: 0xEDEDED)],
                    foreground: Color(hex: 0x111111), secondary: Color(hex: 0x6B7280), badge: Color(hex: 0x111111))
    ]
}

// MARK: - 레이아웃

/// 안내판 형태. 카드형(화면·SNS 공유용)과 A4 세로(인쇄·비치용).
enum PosterLayout: String, CaseIterable, Identifiable {
    case card, a4
    var id: String { rawValue }
    var label: String { self == .card ? "카드" : "A4 포스터" }

    /// 각 레이아웃의 크기·여백·글자 규격
    var metrics: PosterMetrics {
        switch self {
        case .card:
            return PosterMetrics(width: 340, height: nil, padding: 26, spacing: 18,
                                 qrSize: 176, titleSize: 28, logoSize: 52,
                                 fillsHeight: false, exportScale: 3)
        case .a4:
            // A4 비율(210:297)에 맞춘 세로 포스터. 폭은 콘텐츠가 넉넉히 들어가도록
            // 잡고(미리보기는 축소 표시), 인쇄를 위해 해상도를 크게 뽑는다.
            return PosterMetrics(width: 426, height: 426 * 297 / 210, padding: 32, spacing: 18,
                                 qrSize: 210, titleSize: 34, logoSize: 72,
                                 fillsHeight: true, exportScale: 5)
        }
    }
}

struct PosterMetrics {
    let width: CGFloat
    let height: CGFloat?     // nil이면 콘텐츠 크기(카드형)
    let padding: CGFloat
    let spacing: CGFloat
    let qrSize: CGFloat
    let titleSize: CGFloat
    let logoSize: CGFloat
    let fillsHeight: Bool     // 고정 높이를 스페이서로 채울지(A4)
    let exportScale: CGFloat  // 내보내기 해상도 배율
}

// MARK: - 안내판 뷰 (미리보기 + 이미지 내보내기 공용)

/// 실제 인쇄/공유될 안내판. 미리보기와 내보내기가 동일한 결과를 내도록 하나의 뷰로 유지한다.
struct WifiPosterView: View {
    let ssid: String
    let password: String
    let theme: PosterTheme
    let heading: String
    let subtitle: String
    let showPassword: Bool
    let qrImage: UIImage?
    var layout: PosterLayout = .card
    var logoImage: UIImage? = nil
    var storeName: String = ""

    private var m: PosterMetrics { layout.metrics }

    var body: some View {
        VStack(spacing: m.spacing) {
            header
            qrCard
            infoCard
            footer
            // A4는 남는 세로 공간을 아래로 채워 상단 정렬 유지(콘텐츠가 더 길면 프레임이 늘어나 잘리지 않음)
            if m.fillsHeight { Spacer(minLength: 0) }
        }
        .padding(m.padding)
        .frame(minWidth: m.width, maxWidth: m.width, minHeight: m.height ?? 0, alignment: .top)
        .background(theme.gradient)
        .clipShape(RoundedRectangle(cornerRadius: layout == .a4 ? 20 : 26, style: .continuous))
    }

    private var header: some View {
        VStack(spacing: 8) {
            // 매장 로고(선택) — 흰 원형 배지 위에 얹어 어떤 테마에서도 또렷하게
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: m.logoSize, height: m.logoSize)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                    .padding(.bottom, 2)
            }

            if !storeName.isEmpty {
                Text(storeName)
                    .font(.system(size: layout == .a4 ? 20 : 16, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.caption.weight(.bold))
                Text("WiFi")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
            }
            .foregroundStyle(theme.badge)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.badge.opacity(0.18), in: Capsule())

            Text(heading.isEmpty ? "무료 와이파이" : heading)
                .font(.system(size: m.titleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.foreground)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(layout == .a4 ? .body.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// QR은 항상 흰 배경 위 검정 — 어떤 테마에서도 잘 스캔되도록.
    private var qrCard: some View {
        Group {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: m.qrSize, height: m.qrSize)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: m.qrSize, height: m.qrSize)
                    .overlay(ProgressView())
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow(label: "네트워크", value: ssid, mono: false)
            if showPassword {
                Divider().overlay(theme.foreground.opacity(0.12))
                infoRow(label: "비밀번호", value: password.isEmpty ? "없음 (개방)" : password, mono: true)
            }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoRow(label: String, value: String, mono: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(mono ? .callout.weight(.bold).monospaced() : .callout.weight(.bold))
                .foregroundStyle(theme.foreground)
                .textSelection(.enabled)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, layout == .a4 ? 14 : 12)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "qrcode.viewfinder")
            Text("카메라로 QR을 비추면 자동 연결")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(theme.secondary)
    }
}

// MARK: - 안내판 만들기 시트

/// 저장된 네트워크로 손님용 안내판을 꾸며 이미지로 공유·인쇄하는 시트.
/// iOS 기본 QR 공유가 못 하는 "예쁘게 만들어 비치" 니즈를 겨냥한 도구.
struct WifiPosterSheet: View {
    let ssid: String
    let password: String
    @Environment(\.dismiss) private var dismiss

    @State private var theme: PosterTheme = PosterTheme.all[0]
    @State private var heading: String = "무료 와이파이"
    @State private var subtitle: String = "편하게 이용하세요"
    @State private var showPassword: Bool = true
    @State private var qrImage: UIImage?
    @State private var shareItem: ShareImage?
    // 로고 / A4 포스터 옵션
    @State private var layout: PosterLayout = .card
    @State private var storeName: String = ""
    @State private var logoImage: UIImage?
    @State private var logoPickerItem: PhotosPickerItem?

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
            .navigationTitle("안내판 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
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
            ActivityView(image: item.image)
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
        WifiPosterView(ssid: ssid, password: password, theme: theme,
                       heading: heading, subtitle: subtitle,
                       showPassword: showPassword, qrImage: qrImage,
                       layout: layout, logoImage: logoImage, storeName: storeName)
    }

    // MARK: 레이아웃(카드 / A4) 선택

    private var layoutPicker: some View {
        Picker("형태", selection: $layout.animation(.snappy)) {
            ForEach(PosterLayout.allCases) { option in
                Text(option.label).tag(option)
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
                        Button {
                            withAnimation(.snappy) { theme = item }
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(item.gradient)
                                    .frame(width: 52, height: 52)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(theme == item ? Color.accentColor : .clear, lineWidth: 3)
                                    }
                                Text(item.name)
                                    .font(.caption2.weight(theme == item ? .bold : .regular))
                                    .foregroundStyle(theme == item ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: 문구·옵션

    private var controls: some View {
        VStack(spacing: 14) {
            logoRow
            Divider()
            labeledField(title: "매장 이름", text: $storeName, placeholder: "예) 라운지 카페")
            labeledField(title: "제목", text: $heading, placeholder: "무료 와이파이")
            labeledField(title: "안내 문구", text: $subtitle, placeholder: "편하게 이용하세요")
            Toggle(isOn: $showPassword) {
                Label("비밀번호 표시", systemImage: "key.fill")
                    .font(.subheadline)
            }
            .padding(.vertical, 4)
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
                Text(logoImage == nil ? "선택 사항 — 상단에 표시" : "적용됨")
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
                Text(logoImage == nil ? "선택" : "변경")
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

    private func labeledField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
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
        let renderer = ImageRenderer(content: posterView)
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

/// UIActivityViewController 래퍼 — 이미지 저장/공유/AirPrint 인쇄를 한 번에 제공
private struct ActivityView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Color(hex:)

extension Color {
    /// 0xRRGGBB 정수로 색을 만든다 (테마 팔레트 정의용)
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

#Preview {
    WifiPosterSheet(ssid: "CAFE_WIFI_2G", password: "welcome1234")
}
