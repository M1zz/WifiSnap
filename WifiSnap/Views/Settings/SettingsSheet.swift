import SwiftUI
import LeeoKit

/// 설정 — 내 버전(요금제) · 도움말 · 의견 보내기 · 리뷰 · 문의 · 정책 링크.
/// 피드백·리뷰·정책 행은 LeeoKit(LeeoSupportSection)이 계약(WifiSnapSpec)을 보고 채운다.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showOnboarding = false
    @ObservedObject private var purchases = PurchaseManager.shared
    @State private var showPaywall = false
    /// 구독 중인 사람이 평생으로 옮겨 가는 시트 (→ LeeoGraduation)
    @State private var showGraduation = false
    @State private var managingSubscription = false
    @State private var restoring = false
    /// 복원을 눌렀는데 찾지 못한 이유. 누르기 전에는 아무 말도 하지 않는다.
    @State private var restoreMessage: String?

    /// 메일 앱으로 바로 문의 — 제목에 앱 이름과 버전을 넣어 어떤 앱 이야기인지 바로 알 수 있게 한다.
    private var mailURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = WifiSnapSpec.developerEmail
        components.queryItems = [URLQueryItem(name: "subject", value: String(localized: "[마이파이 \(version)] 문의"))]
        return components.url
    }

    // MARK: 내 버전

    /// 무료인가 열려 있는가. ⚠️ 영수증을 아직 못 읽었으면 '무료'라고 단정하지 않는다.
    private var planTitle: String {
        if purchases.tier > .free { return purchases.tier.title }
        return purchases.isKnown ? ProTier.free.title : String(localized: "확인 중…")
    }

    private var planNote: String {
        switch purchases.tier {
        case .pro:
            purchases.isGrandfathered
                ? String(localized: "처음부터 함께해 주셔서 고마워요. Pro를 평생 그대로 쓰세요.")
                : String(localized: "모든 기능이 열려 있어요.")
        case .plus:
            String(localized: "위젯 · 지도 · 단축어 · 캡처로 가져오기는 Pro에서 열려요.")
        case .free:
            String(localized: "찍어서 연결하고 QR로 나누는 일은 계속 무료예요.")
        }
    }

    private var planSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(planTitle)
                    .font(.headline)
                Text(planNote)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)

            if purchases.tier < .pro {
                Button {
                    showPaywall = true
                } label: {
                    Label("요금제 보기", systemImage: "sparkles")
                }
            }
            // 구독 중이면 구독 관리 바로 아래에 평생으로 옮겨 가는 길을 늘 둔다.
            if purchases.subscription != nil {
                Button {
                    managingSubscription = true
                } label: {
                    Label("구독 관리", systemImage: "creditcard")
                }
                Button {
                    showGraduation = true
                } label: {
                    Label(LeeoLadderText.switchToLifetimeEntry, systemImage: "infinity")
                }
            }
            Button {
                Task {
                    restoring = true
                    restoreMessage = nil
                    await purchases.restore()
                    restoreMessage = purchases.tier == .free ? purchases.failureMessage : nil
                    restoring = false
                }
            } label: {
                HStack {
                    Label("구매 복원", systemImage: "arrow.clockwise")
                    if restoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(restoring)
            if let message = restoreMessage {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("내 버전")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // 요금제를 팔기 시작한 뒤에만(상품을 한 번이라도 불러온 기기) 선다. 산 것이 있으면 언제나.
                if purchases.sellsPaid || purchases.tier > .free {
                    planSection
                }

                Section {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("처음 안내 다시 보기", systemImage: "sparkles")
                    }
                } header: {
                    Text("도움말")
                }

                Section {
                    LeeoSupportSection<WifiSnapSpec>()
                    // 앞으로 만들 기능 — 원본은 WifiSnapRoadmap.swift
                    NavigationLink(LeeoRoadmapText.entry) { RoadmapScreen() }
                    // 친구에게 소개하기 — App Store ID 가 없으면 그리지 않는다
                    LeeoShareAppLink<WifiSnapSpec>()
                    // 개발자 응원하기(팁) — 판매 중인 팁이 없으면 그리지 않는다
                    LeeoTipJarLink<WifiSnapSpec>(tipJar: WifiSnapSpec.tipJar)
                } header: {
                    Text("의견 · 리뷰")
                } footer: {
                    Text("보내 주신 의견은 개발자가 하나하나 직접 읽어요.")
                }

                Section {
                    if let mailURL {
                        Link(destination: mailURL) {
                            Label("메일로 문의 (\(WifiSnapSpec.developerEmail))", systemImage: "envelope")
                        }
                    }
                    Link(destination: URL(string: "https://instagram.com/lee25_ios")!) {
                        Label("인스타그램 DM (@lee25_ios)", systemImage: "paperplane")
                    }
                } header: {
                    Text("문의")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료", systemImage: "checkmark") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                WifiSnapOnboardingView { showOnboarding = false }
                    .foldConfined()
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showGraduation) {
                LeeoGraduationOfferView(graduate: purchases.product(ProProduct.graduate)) {
                    await purchases.refresh()
                }
                .presentationDragIndicator(.visible)
            }
            .manageSubscriptionsSheet(isPresented: $managingSubscription)
        }
    }
}
