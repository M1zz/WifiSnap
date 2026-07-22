import SwiftUI
import MapKit

/// 저장된 와이파이를 '연결/공유했던 위치'에 핀으로 표시하는 지도.
/// 위치가 기록된 네트워크만 나오며(스캔만 하고 접속 안 한 건 제외), 핀을 탭하면 그 자리에서 QR 공유.
struct MapSheet: View {
    let networks: [SavedNetwork]
    @Environment(\.dismiss) private var dismiss

    /// 지도에 찍을 수 있는(위치가 있는) 네트워크만
    private var located: [SavedNetwork] {
        networks.filter { $0.coordinate != nil }
    }

    @State private var selectedID: UUID?
    @State private var qrNetwork: SavedNetwork?

    private var selected: SavedNetwork? {
        located.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if located.isEmpty {
                    emptyState
                } else {
                    mapContent
                }
            }
            .navigationTitle("저장한 와이파이 지도")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(item: $qrNetwork) { net in
                QRCodeSheet(ssid: net.ssid, password: net.password)
            }
        }
    }

    private var mapContent: some View {
        Map(selection: $selectedID) {
            UserAnnotation()
            ForEach(located) { net in
                Marker(net.ssid, systemImage: "wifi", coordinate: net.coordinate!)
                    .tint(.green)
                    .tag(net.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .safeAreaInset(edge: .bottom) {
            if let net = selected {
                selectionCard(net)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selectedID)
    }

    /// 선택된 핀의 하단 카드 — SSID + QR 공유
    private func selectionCard(_ net: SavedNetwork) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.green, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(net.ssid)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("여기서 저장한 와이파이")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                qrNetwork = net
            } label: {
                Label("QR", systemImage: "qrcode")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .fixedSize()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "지도에 표시할 위치가 없어요",
            systemImage: "mappin.slash",
            description: Text("와이파이에 연결하거나 '여기'에서 공유하면 그 위치가 지도에 기록돼요.")
        )
    }
}
