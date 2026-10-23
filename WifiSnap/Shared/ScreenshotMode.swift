#if DEBUG
import Foundation
import CoreLocation

/// App Store 스크린샷용 장면 (DEBUG 빌드 전용 — 출시 빌드에는 들어가지 않는다).
///
/// 시뮬레이터에서 `-ScreenshotScene <scan|qr|poster-card|poster-a4|saved>` 로 띄우면
/// 그 언어에 맞는 예시 데이터를 채우고 해당 화면을 바로 연다.
/// 캡처 스크립트: scripts/capture_screenshots.sh
enum ScreenshotMode {
    static var scene: String? { UserDefaults.standard.string(forKey: "ScreenshotScene") }
    static var isActive: Bool { scene != nil }

    /// '여기' 뱃지가 뜨도록 시뮬레이터 위치(simctl location set)와 맞춘 좌표
    static let loungeCoordinate = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)

    static let scanSSID = "Bakery_Moon_5G"
    static let scanPassword = "moonbread24"
    static let loungeSSID = "Lounge_Cafe_5G"
    static let loungePassword = "lounge2026!"

    /// 언어별 예시 문구 — 사용자가 직접 적는 이름이라 앱 번역 카탈로그가 아니라 여기 둔다
    struct Demo {
        let hotspot: String   // 친구 아이폰 핫스팟 이름 ("iPhone" 이 들어가야 핫스팟으로 보인다)
        let bakery: String    // 안내판 사진에 함께 찍힌 가게 이름
        let store: String     // 안내판에 인쇄할 매장 이름
        let signName: String  // 안내판 목록에서 구분하는 이름
        let hours: String     // 안내판에 덧붙인 영업시간 줄
    }

    static let demos: [String: Demo] = [
        "ko": Demo(hotspot: "지수의 iPhone", bakery: "달빛 베이커리", store: "라운지 카페", signName: "1층 카운터", hours: "영업시간 09:00 - 22:00"),
        "en": Demo(hotspot: "Emma’s iPhone", bakery: "Moonlight Bakery", store: "Lounge Café", signName: "Front counter", hours: "Open 9 AM – 10 PM"),
        "en-GB": Demo(hotspot: "Olivia’s iPhone", bakery: "Moonlight Bakery", store: "Lounge Café", signName: "Front counter", hours: "Open 09:00–22:00"),
        "zh-Hans": Demo(hotspot: "小雨的 iPhone", bakery: "月光烘焙坊", store: "休闲咖啡馆", signName: "一楼前台", hours: "营业时间 09:00 - 22:00"),
        "zh-Hant": Demo(hotspot: "小雨的 iPhone", bakery: "月光烘焙坊", store: "悠閒咖啡廳", signName: "一樓櫃檯", hours: "營業時間 09:00 - 22:00"),
        "ja": Demo(hotspot: "さくらのiPhone", bakery: "月あかりベーカリー", store: "ラウンジカフェ", signName: "1階カウンター", hours: "営業時間 9:00〜22:00"),
        "ru": Demo(hotspot: "iPhone Анны", bakery: "Пекарня «Луна»", store: "Кафе «Лаунж»", signName: "Стойка на 1 этаже", hours: "Открыто с 9:00 до 22:00"),
        "es": Demo(hotspot: "iPhone de Lucía", bakery: "Panadería Luna", store: "Café Lounge", signName: "Mostrador", hours: "Horario: 9:00 – 22:00"),
        "de": Demo(hotspot: "iPhone von Lena", bakery: "Bäckerei Mondschein", store: "Lounge Café", signName: "Theke unten", hours: "Geöffnet 9–22 Uhr"),
        "fr": Demo(hotspot: "iPhone de Léa", bakery: "Boulangerie Clair de Lune", store: "Lounge Café", signName: "Comptoir", hours: "Ouvert de 9 h à 22 h"),
        "it": Demo(hotspot: "iPhone di Giulia", bakery: "Forno Chiaro di Luna", store: "Lounge Café", signName: "Bancone", hours: "Aperto 9:00 – 22:00"),
        "pt-BR": Demo(hotspot: "iPhone da Ana", bakery: "Padaria Luar", store: "Lounge Café", signName: "Balcão", hours: "Aberto das 9h às 22h"),
        "th": Demo(hotspot: "iPhone ของมิว", bakery: "ร้านขนมปังแสงจันทร์", store: "เลานจ์คาเฟ่", signName: "เคาน์เตอร์ชั้น 1", hours: "เปิด 09:00 - 22:00 น."),
        "vi": Demo(hotspot: "iPhone của Lan", bakery: "Tiệm bánh Ánh Trăng", store: "Lounge Café", signName: "Quầy tầng 1", hours: "Mở cửa 9:00 - 22:00"),
        "cs": Demo(hotspot: "Terezin iPhone", bakery: "Pekárna U Měsíce", store: "Kavárna Lounge", signName: "Pult v přízemí", hours: "Otevřeno 9:00–22:00"),
        "da": Demo(hotspot: "Idas iPhone", bakery: "Bageriet Månelys", store: "Lounge Café", signName: "Disken", hours: "Åbent 9-22"),
        "el": Demo(hotspot: "iPhone της Μαρίας", bakery: "Φούρνος Φεγγάρι", store: "Lounge Café", signName: "Πάγκος ισογείου", hours: "Ανοιχτά 09:00 - 22:00"),
        "fi": Demo(hotspot: "Ainon iPhone", bakery: "Leipomo Kuutamo", store: "Lounge Café", signName: "Kassa", hours: "Avoinna 9–22"),
        "id": Demo(hotspot: "iPhone Sari", bakery: "Toko Roti Rembulan", store: "Lounge Café", signName: "Meja kasir", hours: "Buka 09.00 - 22.00"),
        "nb": Demo(hotspot: "Noras iPhone", bakery: "Månelys bakeri", store: "Lounge Café", signName: "Disken", hours: "Åpent 09–22"),
        "nl": Demo(hotspot: "iPhone van Sanne", bakery: "Bakkerij Maanlicht", store: "Lounge Café", signName: "Balie beneden", hours: "Open 9.00 - 22.00 uur"),
        "pl": Demo(hotspot: "iPhone Zosi", bakery: "Piekarnia Księżyc", store: "Kawiarnia Lounge", signName: "Lada na parterze", hours: "Czynne 9:00–22:00"),
        "sv": Demo(hotspot: "Elsas iPhone", bakery: "Bageriet Månsken", store: "Lounge Café", signName: "Disken", hours: "Öppet 9–22"),
        "tr": Demo(hotspot: "Elif’in iPhone’u", bakery: "Ay Işığı Fırını", store: "Lounge Kafe", signName: "Giriş kasası", hours: "Açık 09.00 - 22.00"),
    ]

    static var demo: Demo {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if let exact = demos[preferred] { return exact }
        let locale = Locale(identifier: preferred)
        let language = locale.language.languageCode?.identifier ?? "en"
        if language == "zh" {
            return demos[locale.language.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"]!
        }
        if language == "en", locale.region?.identifier == "GB" { return demos["en-GB"]! }
        if language == "pt" { return demos["pt-BR"]! }
        if language == "no" || language == "nn" { return demos["nb"]! }
        return demos[language] ?? demos["en"]!
    }

    /// 앱 시작 시(저장소들이 읽기 전에) 예시 데이터를 심는다
    static func seedIfNeeded() {
        guard isActive else { return }
        let d = demo
        let now = Date()
        func network(_ ssid: String, _ password: String, minutesAgo: Double,
                     coordinate: CLLocationCoordinate2D? = nil, hotspot: Bool = false) -> SavedNetwork {
            SavedNetwork(ssid: ssid, password: password, savedAt: now.addingTimeInterval(-minutesAgo * 60),
                         latitude: coordinate?.latitude, longitude: coordinate?.longitude, isHotspot: hotspot)
        }
        let networks = [
            network(d.hotspot, "sunny-day-77", minutesAgo: 5, hotspot: true),
            network(loungeSSID, loungePassword, minutesAgo: 30, coordinate: loungeCoordinate),
            network("Home_iptime", "home12345", minutesAgo: 600,
                    coordinate: CLLocationCoordinate2D(latitude: 37.50, longitude: 127.03)),
            network("Office-Guest", "welcome2026", minutesAgo: 2000,
                    coordinate: CLLocationCoordinate2D(latitude: 37.40, longitude: 127.10)),
            network("Seaside_Stay", "oceanview88", minutesAgo: 9000,
                    coordinate: CLLocationCoordinate2D(latitude: 35.16, longitude: 129.16)),
        ]
        if let data = try? JSONEncoder().encode(networks) {
            SharedDefaults.store.set(data, forKey: SharedDefaults.savedNetworksKey)
        }

        let a4 = scene == "poster-a4"
        let design = PosterDesign(name: d.signName,
                                  storeName: d.store,
                                  extraLines: [d.hours],
                                  themeID: a4 ? "midnight" : "cafe",
                                  layoutID: a4 ? PosterLayout.a4.rawValue : PosterLayout.card.rawValue)
        if let data = try? JSONEncoder().encode([design]) {
            UserDefaults.standard.set(data, forKey: "wifisnap.poster.designs")
        }
        UserDefaults.standard.removeObject(forKey: "wifisnap.known.ssids")
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
    }
}
#endif
