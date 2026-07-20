import SwiftUI

/// 저장된 네트워크의 연결용 QR을 보여주고 공유하는 시트
struct QRCodeSheet: View {
    let ssid: String
    let password: String
    @Environment(\.dismiss) private var dismiss

    @State private var qrImage: UIImage?
    @State private var isGenerating = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isGenerating {
                    // QR 생성 중 — 사용자가 기다려야 함을 알림
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("QR 만드는 중…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else if let uiImage = qrImage {
                    Image(uiImage: uiImage)
                        .interpolation(.none)   // QR은 픽셀이 뭉개지면 안 됨
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 4)

                    VStack(spacing: 4) {
                        Text(ssid).font(.headline)
                        Text("카메라로 비추면 바로 연결돼요")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ShareLink(
                        item: Image(uiImage: uiImage),
                        preview: SharePreview("\(ssid) 와이파이 QR", image: Image(uiImage: uiImage))
                    ) {
                        Label("QR 이미지 공유", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView("QR 생성 실패",
                                           systemImage: "qrcode",
                                           description: Text("네트워크 정보를 확인해 주세요."))
                }
            }
            .padding()
            .navigationTitle("연결용 QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            // 무거운 QR 렌더링을 백그라운드에서 수행 → 시트 애니메이션이 끊기지 않음
            let ssid = self.ssid
            let password = self.password
            let image = await Task.detached(priority: .userInitiated) {
                QRCodeGenerator.wifiQRImage(ssid: ssid, password: password)
            }.value
            qrImage = image
            isGenerating = false
        }
    }
}
