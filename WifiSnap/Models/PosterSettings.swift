import Foundation

/// 안내판 설정이 전역 한 벌이던 시절의 저장 키.
///
/// 지금은 안내판이 문서 단위(`PosterDesign`)라서, 이 키들은 **예전 값을 한 번 옮겨오는 용도**로만 남아 있다.
/// 테마 조회 헬퍼도 여기 두어 여러 화면이 공유한다.
enum PosterSettings {

    // MARK: 저장 키

    static let storeNameKey    = "wifisnap.poster.storeName"
    static let headingKey      = "wifisnap.poster.heading"
    static let subtitleKey     = "wifisnap.poster.subtitle"
    static let showPasswordKey = "wifisnap.poster.showPassword"
    static let themeKey        = "wifisnap.poster.themeID"
    static let layoutKey       = "wifisnap.poster.layoutID"

    // MARK: 기본값

    static let defaultStoreName    = ""
    static let defaultHeading      = "무료 와이파이"
    static let defaultSubtitle     = "편하게 이용하세요"
    static let defaultShowPassword = true
    static var defaultThemeID: String { PosterTheme.all[0].id }
    static var defaultLayoutID: String { PosterLayout.card.rawValue }

    /// 저장된 id로 테마를 찾는다. 알 수 없는 id(앱 업데이트로 테마가 사라진 경우)면 첫 테마로.
    static func theme(id: String) -> PosterTheme {
        PosterTheme.all.first { $0.id == id } ?? PosterTheme.all[0]
    }

    /// 전역 설정 시절의 값을 안내판 문서 한 장으로 옮긴다 (앱 업데이트 시 1회).
    /// 저장해 둔 문구가 있으면 그대로 살리고, 없으면 기본 안내판이 된다.
    static func migratedDesign() -> PosterDesign {
        let defaults = UserDefaults.standard
        return PosterDesign(
            name: "내 안내판",
            storeName: defaults.string(forKey: storeNameKey) ?? defaultStoreName,
            heading: defaults.string(forKey: headingKey) ?? defaultHeading,
            subtitle: defaults.string(forKey: subtitleKey) ?? defaultSubtitle,
            showPassword: defaults.object(forKey: showPasswordKey) as? Bool ?? defaultShowPassword,
            themeID: defaults.string(forKey: themeKey) ?? defaultThemeID,
            layoutID: defaults.string(forKey: layoutKey) ?? defaultLayoutID
        )
    }
}
