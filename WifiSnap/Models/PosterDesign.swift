import Foundation
import SwiftUI

/// 손님용 안내판 한 장. 매장마다·자리마다 다른 안내판을 만들 수 있도록 문서 단위로 저장한다.
///
/// 안내판에 인쇄되는 글자는 라벨까지 전부 여기 들어 있다 — 사장님이 원하는 말로 바꿔 쓰라고.
/// (예: "비밀번호" → "PW", "네트워크" → "와이파이 이름")
struct PosterDesign: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// 목록에서 구분하려고 붙이는 이름. 안내판에는 인쇄되지 않는다.
    var name: String = "새 안내판"

    // MARK: 인쇄되는 글자 (전부 수정 가능)
    var storeName: String = ""
    var badge: String = "WiFi"
    var heading: String = "무료 와이파이"
    var subtitle: String = "편하게 이용하세요"
    var networkLabel: String = "네트워크"
    var passwordLabel: String = "비밀번호"
    var footer: String = "카메라로 QR을 비추면 자동 연결"
    /// 영업시간·인스타 계정처럼 매장이 덧붙이고 싶은 줄 (원하는 만큼)
    var extraLines: [String] = []

    // MARK: 표시 옵션
    var showPassword: Bool = true
    var themeID: String = PosterTheme.all[0].id
    var layoutID: String = PosterLayout.card.rawValue
    var updatedAt: Date = Date()

    var theme: PosterTheme { PosterSettings.theme(id: themeID) }
    var layout: PosterLayout { PosterLayout(rawValue: layoutID) ?? .card }

    /// 실제로 인쇄할 자유 텍스트 줄 (빈 줄 제외)
    var visibleExtraLines: [String] {
        extraLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 목록에서 보여줄 한 줄 요약
    var summary: String {
        [storeName, heading, subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// 안내판 문서 저장소 (UserDefaults). 최근에 고친 것이 항상 맨 앞에 온다.
@MainActor
final class PosterDesignStore: ObservableObject {
    @Published private(set) var designs: [PosterDesign] = []

    private let storageKey = "wifisnap.poster.designs"

    init() {
        load()
    }

    /// 메인 화면 카드에 보여줄 안내판 — 가장 최근에 고친 것
    var current: PosterDesign {
        designs.first ?? PosterDesign(name: "내 안내판")
    }

    /// 저장/갱신. 고친 것을 맨 앞으로 올려 '최근 것'이 메인 카드에 뜨게 한다.
    func save(_ design: PosterDesign) {
        var updated = design
        updated.updatedAt = Date()
        designs.removeAll { $0.id == updated.id }
        designs.insert(updated, at: 0)
        persist()
    }

    @discardableResult
    func addNew() -> PosterDesign {
        let design = PosterDesign(name: "안내판 \(designs.count + 1)")
        designs.insert(design, at: 0)
        persist()
        return design
    }

    @discardableResult
    func duplicate(_ design: PosterDesign) -> PosterDesign {
        var copy = design
        copy.id = UUID()
        copy.name = "\(design.name) 사본"
        copy.updatedAt = Date()
        designs.insert(copy, at: 0)
        persist()
        return copy
    }

    func delete(id: UUID) {
        designs.removeAll { $0.id == id }
        // 하나도 없으면 빈 화면이 되므로 기본 안내판을 다시 만들어 둔다
        if designs.isEmpty { designs = [PosterDesign(name: "내 안내판")] }
        persist()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PosterDesign].self, from: data),
           !decoded.isEmpty {
            designs = decoded
            return
        }
        // 전역 설정 한 벌만 쓰던 시절의 값을 안내판 한 장으로 옮긴다
        designs = [PosterSettings.migratedDesign()]
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(designs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
