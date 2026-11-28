import SwiftUI

// 안내판의 모양(테마 · 형태)과 안내판 그림 자체. 아이폰의 안내판 시트와 맥의 인쇄가 같은 그림을 쓴다.

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
        PosterTheme(id: "midnight", name: String(localized: "미드나잇"),
                    colors: [Color(hex: 0x1E1B4B), Color(hex: 0x4338CA), Color(hex: 0x7C3AED)],
                    foreground: .white, secondary: Color(hex: 0xC7D2FE), badge: Color(hex: 0x34D399)),
        PosterTheme(id: "sunset", name: String(localized: "선셋"),
                    colors: [Color(hex: 0xFF6B6B), Color(hex: 0xFF8E53), Color(hex: 0xFFB088)],
                    foreground: .white, secondary: Color(hex: 0xFFF1E6), badge: .white),
        PosterTheme(id: "mint", name: String(localized: "민트"),
                    colors: [Color(hex: 0x06B6D4), Color(hex: 0x10B981)],
                    foreground: .white, secondary: Color(hex: 0xE0F7F4), badge: .white),
        PosterTheme(id: "ocean", name: String(localized: "오션"),
                    colors: [Color(hex: 0x2563EB), Color(hex: 0x0EA5E9), Color(hex: 0x22D3EE)],
                    foreground: .white, secondary: Color(hex: 0xDBEAFE), badge: .white),
        PosterTheme(id: "forest", name: String(localized: "포레스트"),
                    colors: [Color(hex: 0x065F46), Color(hex: 0x059669), Color(hex: 0x34D399)],
                    foreground: .white, secondary: Color(hex: 0xD1FAE5), badge: .white),
        PosterTheme(id: "cafe", name: String(localized: "카페"),
                    colors: [Color(hex: 0xF5E9DA), Color(hex: 0xE8D3B5)],
                    foreground: Color(hex: 0x5B3A29), secondary: Color(hex: 0x8A6E56), badge: Color(hex: 0xB5835A)),
        PosterTheme(id: "mono", name: String(localized: "모노"),
                    colors: [Color(hex: 0xFAFAFA), Color(hex: 0xEDEDED)],
                    foreground: Color(hex: 0x111111), secondary: Color(hex: 0x6B7280), badge: Color(hex: 0x111111))
    ]
}

// MARK: - 레이아웃

/// 안내판 형태. 카드형(화면·SNS 공유용)과 A4 세로(인쇄·비치용).
enum PosterLayout: String, CaseIterable, Identifiable {
    case card, a4
    var id: String { rawValue }
    var label: String { self == .card ? String(localized: "카드") : String(localized: "A4 포스터") }

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
    let design: PosterDesign
    let qrImage: PlatformImage?
    var logoImage: PlatformImage? = nil

    private var theme: PosterTheme { design.theme }
    private var layout: PosterLayout { design.layout }
    private var m: PosterMetrics { layout.metrics }

    var body: some View {
        VStack(spacing: m.spacing) {
            header
            qrCard
            infoCard
            extraLines
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
                Image(platformImage: logoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: m.logoSize, height: m.logoSize)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                    .padding(.bottom, 2)
            }

            if !design.storeName.isEmpty {
                Text(design.storeName)
                    .font(.system(size: layout == .a4 ? 20 : 16, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            // 뱃지 문구를 비우면 뱃지 자체가 사라진다 (원하지 않는 사장님도 있으므로)
            if !design.badge.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "wifi")
                        .font(.caption.weight(.bold))
                    Text(design.badge)
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                }
                .foregroundStyle(theme.badge)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.badge.opacity(0.18), in: Capsule())
            }

            if !design.heading.isEmpty {
                Text(design.heading)
                    .font(.system(size: m.titleSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
            }

            if !design.subtitle.isEmpty {
                Text(design.subtitle)
                    .font(layout == .a4 ? .body.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// 매장이 덧붙인 자유 텍스트 줄 (영업시간·인스타 계정 등)
    @ViewBuilder
    private var extraLines: some View {
        let lines = design.visibleExtraLines
        if !lines.isEmpty {
            VStack(spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .multilineTextAlignment(.center)
                }
            }
            .font(layout == .a4 ? .subheadline.weight(.medium) : .caption.weight(.medium))
            .foregroundStyle(theme.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    /// QR은 항상 흰 배경 위 검정 — 어떤 테마에서도 잘 스캔되도록.
    private var qrCard: some View {
        Group {
            if let qrImage {
                Image(platformImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: m.qrSize, height: m.qrSize)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
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
            infoRow(label: design.networkLabel, value: ssid, mono: false)
            if design.showPassword {
                Divider().overlay(theme.foreground.opacity(0.12))
                infoRow(label: design.passwordLabel,
                        value: password.isEmpty ? String(localized: "없음 (개방)") : password,
                        mono: !password.isEmpty)
            }
        }
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoRow(label: String, value: String, mono: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondary)
                .fixedSize()   // 라벨을 바꿔 쓸 수 있으므로 고정 폭 대신 글자에 맞춘다
                .frame(minWidth: 58, alignment: .leading)
            Text(value.bidiIsolated)
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

    @ViewBuilder
    private var footer: some View {
        if !design.footer.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "qrcode.viewfinder")
                Text(design.footer)
                    .multilineTextAlignment(.center)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(theme.secondary)
        }
    }
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
