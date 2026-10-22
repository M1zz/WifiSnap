import SwiftUI

/// 첫 실행 안내 — 이 앱이 해 주는 세 가지를 한 장씩 보여 준다.
/// 처음 연 사용자에게 한 번(ContentView 의 hasSeenOnboarding), 이후엔 설정 > 처음 안내 다시 보기.
struct WifiSnapOnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    private struct Page {
        let symbol: String
        let tint: Color
        let title: String
        let message: String
    }

    private let pages: [Page] = [
        Page(symbol: "qrcode",
             tint: .green,
             title: String(localized: "보여주기만 하면 연결"),
             message: String(localized: "지금 연결된 와이파이를 QR로 보여 주세요.\n친구가 카메라로 비추면 비밀번호를 몰라도 바로 연결돼요.")),
        Page(symbol: "camera.viewfinder",
             tint: .blue,
             title: String(localized: "사진 한 장으로 연결"),
             message: String(localized: "카페·숙소의 와이파이 안내문을 찍거나 앨범에서 고르세요.\n이름과 비밀번호를 읽어 이 폰을 연결해 줘요.")),
        Page(symbol: "doc.text.image",
             tint: .indigo,
             title: String(localized: "손님용 안내판 만들기"),
             message: String(localized: "매장이나 집에 둘 와이파이 안내판을 만들어\n인쇄하거나 이미지로 공유할 수 있어요."))
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("건너뛰기", action: onFinish)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(isLastPage ? 0 : 1)
                    .disabled(isLastPage)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if isLastPage {
                    onFinish()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(isLastPage ? String(localized: "시작하기") : String(localized: "다음"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: page.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 120, height: 120)
                .background(page.tint, in: RoundedRectangle(cornerRadius: 28))
                .accessibilityHidden(true)
            Text(page.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(page.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        // 그림·제목·설명을 한 덩어리로 읽어 VoiceOver 가 장마다 한 번에 안내한다
        .accessibilityElement(children: .combine)
    }
}
