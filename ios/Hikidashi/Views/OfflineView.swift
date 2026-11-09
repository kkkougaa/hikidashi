import AVKit
import SwiftUI
import HikidashiCore

/// 오프라인 보기: 받아 둔 그때 모습 그대로. 그림·영상은 기기에 받은 파일로 (인터넷 없이)
struct OfflineView: View {
    let id: String
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var pack: OfflinePack?
    @State private var loaded = false
    @State private var player: AVPlayer?

    private func local(_ url: String?) -> URL? {
        guard let url, let name = pack?.media[url] else { return nil }
        return OfflineDisk.file(id, name)
    }

    private func image(_ url: String?) -> UIImage? { local(url).flatMap { UIImage(contentsOfFile: $0.path) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let pack {
                    content(pack)
                } else if loaded {
                    ContentUnavailableView("오프라인 저장이 없어요", systemImage: "icloud.slash")
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .navigationTitle("오프라인 보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("오프라인 보기 닫기")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let s = pack?.item.url, let u = URL(string: s) {
                        Button { openURL(u) } label: { Image(systemName: "safari") }.accessibilityLabel("원본 열기")
                    }
                    Button(role: .destructive) { dismiss(); store.removeOffline(id) } label: { Image(systemName: "trash") }
                        .accessibilityLabel("오프라인 저장 지우기")
                }
            }
        }
        .task {
            pack = OfflineDisk.load(id)
            loaded = true
            if let v = local(pack?.item.video) { player = AVPlayer(url: v) }
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder private func content(_ p: OfflinePack) -> some View {
        let it = p.item
        let a = p.article
        VStack(alignment: .leading, spacing: 14) {
            if let s = it.url { SourceChip(url: s, siteName: it.siteName ?? a?.siteName) }
            Text(it.title.isEmpty ? (a?.title ?? it.displayTitle) : it.title).font(.title2.weight(.bold))
            Text("오프라인 저장 · \(store.dates.stamp(p.savedAt))\(p.failed > 0 ? " · 받지 못한 그림·영상 \(p.failed)개" : "")")
                .font(.footnote).foregroundStyle(.secondary)
            if let player {
                VideoPlayer(player: player)
                    // 세로 영상도 가로 영상도 잘리지 않게 (남는 자리는 검게)
                    .frame(height: 440)
                    .background(Color.black)
                    .clipShape(.rect(cornerRadius: 14))
            }
            if !it.note.isEmpty {
                if it.kind == .memo { RichTextView(text: it.note) } else { Text(it.note).font(.body).lineSpacing(4).textSelection(.enabled) }
            }
            if player == nil {
                let photos = (it.images.isEmpty ? [it.image].compactMap { $0 }.filter { !$0.contains("profile_images") } : it.images).compactMap(image)
                ForEach(Array(photos.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img).resizable().scaledToFit().clipShape(.rect(cornerRadius: 14))
                }
            }
            if let a {
                if let hero = image(a.image), it.images.isEmpty, image(it.image) == nil {
                    Image(uiImage: hero).resizable().scaledToFit().clipShape(.rect(cornerRadius: 14))
                }
                ForEach(Array(a.blocks.enumerated()), id: \.offset) { _, b in block(b) }
            }
        }
        .padding(20)
    }

    @ViewBuilder private func block(_ b: ReaderBlock) -> some View {
        switch b {
        case .heading(let t, let level): Text(t).font(level <= 2 ? .title3.weight(.bold) : .headline)
        case .paragraph(let t): Text(t).font(.body).lineSpacing(5).textSelection(.enabled)
        case .quote(let t): Text(t).font(.body).italic().foregroundStyle(.secondary).padding(.leading, 12)
            .overlay(alignment: .leading) { Rectangle().fill(Color.brand.opacity(0.5)).frame(width: 3) }
        case .listItem(let t): HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•").foregroundStyle(.secondary); Text(t) }
        case .code(let t): Text(t).font(.system(.callout, design: .monospaced)).padding(10).background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
        case .image(let s): if let img = image(s) { Image(uiImage: img).resizable().scaledToFit().clipShape(.rect(cornerRadius: 12)) }
        }
    }
}
