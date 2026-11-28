import SwiftUI

/// 메뉴 막대를 누르면 나오는 판. 지금 와이파이와 저장한 와이파이가 있고, 하나를 누르면 QR 이 크게 뜬다.
struct MacMenuBarPanel: View {
    @EnvironmentObject private var store: NetworkStore
    @EnvironmentObject private var reader: MacWifiReader
    @ObservedObject private var purchases = PurchaseManager.shared
    @Environment(\.openWindow) private var openWindow

    @State private var addingManually = false

    private var current: SavedNetwork? { reader.ssid.flatMap { store.network(for: $0) } }
    private var others: [SavedNetwork] { store.networks.filter { $0.id != current?.id } }
    private var canAdd: Bool {
        store.networks.count < FreeLimit.savedNetworks || purchases.allows(.unlimitedNetworks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentSection
            Divider()
            savedSection
            Divider()
            HStack {
                Button(addingManually ? "닫기" : "와이파이 추가") {
                    withAnimation(.snappy) { addingManually.toggle() }
                }
                Spacer()
                Button("끝내기") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { reader.refresh() }
    }

    // MARK: 지금 와이파이

    @ViewBuilder
    private var currentSection: some View {
        Text("지금 연결됨")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        if reader.needsPermission {
            VStack(alignment: .leading, spacing: 6) {
                Text("와이파이 이름을 읽으려면 위치 접근을 허용해 주세요.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("허용하기") { reader.requestPermission() }
            }
        } else if let current {
            row(current, isCurrent: true)
        } else if let ssid = reader.ssid {
            // 처음 보는 와이파이 — 맥은 비밀번호를 알려 주지 않으니 한 번만 받는다
            MacAddNetworkForm(fixedSSID: ssid, canAdd: canAdd)
        } else {
            Text("연결된 와이파이가 없어요")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 저장한 와이파이

    @ViewBuilder
    private var savedSection: some View {
        if addingManually {
            MacAddNetworkForm(fixedSSID: nil, canAdd: canAdd) { addingManually = false }
        }
        Text("저장한 와이파이")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        if others.isEmpty {
            Text("아직 저장한 와이파이가 없어요")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(others) { row($0, isCurrent: false) }
                }
            }
            .frame(maxHeight: 260)
            .fixedSize(horizontal: false, vertical: others.count < 7)
        }
    }

    private func row(_ network: SavedNetwork, isCurrent: Bool) -> some View {
        Button {
            showQR(network)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCurrent ? "wifi" : "qrcode")
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                    .frame(width: 18)
                Text(network.ssid.bidiIsolated)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "QR 크게 보기"))
        .contextMenu {
            Button("QR 크게 보기") { showQR(network) }
            Button("삭제", role: .destructive) { store.delete(ids: [network.id]) }
        }
    }

    private func showQR(_ network: SavedNetwork) {
        openWindow(id: MacQRWindow.id, value: network.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 와이파이 하나를 맥에 기억시킨다. 이름이 정해져 있으면(지금 와이파이) 비밀번호만 받는다.
struct MacAddNetworkForm: View {
    let fixedSSID: String?
    let canAdd: Bool
    var onSaved: () -> Void = {}

    @EnvironmentObject private var store: NetworkStore
    @Environment(\.openWindow) private var openWindow
    @State private var ssid = ""
    @State private var password = ""

    private var name: String { (fixedSSID ?? ssid).trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fixedSSID {
                Text(fixedSSID.bidiIsolated)
                    .font(.headline)
                    .lineLimit(1)
            } else {
                TextField("와이파이 이름", text: $ssid)
            }
            SecureField("비밀번호", text: $password)
                .onSubmit(save)
            Text("맥은 비밀번호를 알려 주지 않아요. 한 번만 넣어 두면 기억해요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if canAdd {
                Button("저장하고 QR 보기", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
            } else {
                Text("무료로 저장할 수 있는 와이파이를 다 채웠어요.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func save() {
        guard canAdd, !name.isEmpty else { return }
        store.upsert(ssid: name, password: password, verifiedName: fixedSSID != nil)
        if let saved = store.network(for: name) {
            openWindow(id: MacQRWindow.id, value: saved.id)
            NSApp.activate(ignoringOtherApps: true)
        }
        ssid = ""
        password = ""
        onSaved()
    }
}
