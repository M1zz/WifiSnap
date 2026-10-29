import SwiftUI
import LeeoKit

/// 설정 — 도움말 · 의견 보내기 · 리뷰 · 문의 · 정책 링크.
/// 피드백·리뷰·정책 행은 LeeoKit(LeeoSupportSection)이 계약(WifiSnapSpec)을 보고 채운다.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showOnboarding = false

    /// 메일 앱으로 바로 문의 — 제목에 앱 이름과 버전을 넣어 어떤 앱 이야기인지 바로 알 수 있게 한다.
    private var mailURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = WifiSnapSpec.developerEmail
        components.queryItems = [URLQueryItem(name: "subject", value: String(localized: "[마이파이 \(version)] 문의"))]
        return components.url
    }

    var body: some View {
        NavigationStack {
            List {
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
                    Button("완료") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                WifiSnapOnboardingView { showOnboarding = false }
            }
        }
    }
}
