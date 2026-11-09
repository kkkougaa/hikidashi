import AVFoundation
import CryptoKit
import SwiftUI
import HikidashiCore

/// 항목 아이콘: 고른 이모지 → 글 대표 이미지 → 사이트 로고 → 서랍 색 블록
struct ItemIcon: View {
    let item: Item
    let folder: Folder?
    var size: CGFloat = 44

    @State private var imageFailed = false
    @State private var logoFailed = false

    private var corner: CGFloat { size * 0.27 }

    var body: some View {
        Group {
            if let emoji = item.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: size * 0.58))
                    .frame(width: size, height: size)
                    .background(Color(.secondarySystemFill), in: .rect(cornerRadius: corner))
            } else if item.kind == .link, let image = item.image, !imageFailed, let url = URL(string: image) {
                CachedImage(url: url.absoluteString, onFail: { imageFailed = true }) { $0.resizable().scaledToFill() } placeholder: { Color(.secondarySystemFill) }
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: corner))
                .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(.primary.opacity(0.08)))
            } else if item.kind == .link, !logoFailed, let logo = logoURL(item.url, size: 128).flatMap(URL.init(string:)) {
                CachedImage(url: logo.absoluteString, onFail: { logoFailed = true }) { $0.resizable().scaledToFit().padding(size * 0.2) } placeholder: { Color.clear }
                .frame(width: size, height: size)
                .background(Color(.systemBackground), in: .rect(cornerRadius: corner))
                .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(.primary.opacity(0.1)))
            } else {
                let letter = item.kind == .memo ? nil : String(domain(of: item.url).prefix(1)).uppercased()
                ZStack {
                    RoundedRectangle(cornerRadius: corner).fill(folder?.color.color ?? unfiledColor)
                    if let letter, !letter.isEmpty {
                        Text(letter).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Image(systemName: "note.text").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 출처 사이트 칩: 로고 + 사이트 이름(없으면 도메인)
struct SourceChip: View {
    let url: String
    var siteName: String?

    var body: some View {
        let host = domain(of: url)
        HStack(spacing: 5) {
            CachedImage(url: logoURL(url, size: 32) ?? "") { $0.resizable().scaledToFit() } placeholder: {
                Text(host.prefix(1).uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 14, height: 14).background(Color.secondary, in: .rect(cornerRadius: 3))
            }
            .frame(width: 14, height: 14)
            .clipShape(.rect(cornerRadius: 3))
            Text(siteName ?? host).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.leading, 6).padding(.trailing, 8)
        .frame(height: 22)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 6))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 서랍 이름표
struct FolderPill: View {
    let folder: Folder?
    var body: some View {
        if let folder {
            Text(folder.name).font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 8).frame(height: 22)
                .background(folder.color.color, in: .rect(cornerRadius: 6))
                .lineLimit(1)
        } else {
            Text("미분류").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).frame(height: 22)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.separator)))
        }
    }
}

/// 이름표 · 출처 칩 · 태그 줄
struct MetaRow: View {
    let item: Item
    let folder: Folder?
    let showFolder: Bool

    var body: some View {
        HStack(spacing: 6) {
            if item.brokenAt != nil { BrokenBadge() }
            if showFolder { FolderPill(folder: folder) }
            if item.kind == .link, let url = item.url { SourceChip(url: url, siteName: item.siteName) }
            ForEach(item.tags, id: \.self) { t in
                Text("#\(t)").font(.footnote).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
        }
        .lineLimit(1)
    }
}

/// 칩을 줄바꿈하며 늘어놓는 배치
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            // 줄보다 넓은 칩은 줄 너비로 줄인다 (말줄임)
            let size = s.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// 그림을 받아 두고 비율도 기억한다. 줄인 그림을 기기(Caches/thumbs)에 저장해서 다음엔 인터넷 없이 보여준다
enum ImageCache {
    private static let images = NSCache<NSString, UIImage>()
    @MainActor private static var ratios: [String: CGFloat] = [:]

    static let folder: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func file(_ url: String) -> URL {
        let digest = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(digest + ".jpg")
    }

    static func image(_ url: String) -> UIImage? {
        if let hit = images.object(forKey: url as NSString) { return hit }
        guard let data = try? Data(contentsOf: file(url)), let img = UIImage(data: data) else { return nil }
        images.setObject(img, forKey: url as NSString)
        return img
    }

    /// 세로 ÷ 가로. 너무 길거나 납작하지 않게 자른다
    @MainActor static func ratio(_ url: String?) -> CGFloat? { url.flatMap { ratios[$0] } }

    @MainActor static func remember(_ img: UIImage, for url: String) {
        images.setObject(img, forKey: url as NSString)
        if img.size.width > 0 { ratios[url] = min(1.6, max(0.45, img.size.height / img.size.width)) }
    }

    static func load(_ url: String) async -> UIImage? {
        if let hit = image(url) {
            await remember(hit, for: url)
            return hit
        }
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let img = UIImage(data: data) else { return nil }
        // 큰 그림은 줄여서 메모리와 저장 공간을 아낀다
        let maxSide: CGFloat = 900
        let s = img.size
        let small: UIImage
        if max(s.width, s.height) > maxSide {
            let k = maxSide / max(s.width, s.height)
            small = await img.byPreparingThumbnail(ofSize: CGSize(width: s.width * k, height: s.height * k)) ?? img
        } else {
            small = img
        }
        if let jpg = small.jpegData(compressionQuality: 0.8) { try? jpg.write(to: file(url), options: .atomic) }
        await remember(small, for: url)
        return small
    }

    /// 저장된 그림 크기 (바이트)
    static func diskSize() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// 너무 커지면 오래된 것부터 지운다
    static func trim(maxBytes: Int = 200_000_000) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        var files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []).compactMap { u -> (URL, Int, Date)? in
            guard let v = try? u.resourceValues(forKeys: keys) else { return nil }
            return (u, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }
        var total = files.reduce(0) { $0 + $1.1 }
        guard total > maxBytes else { return }
        files.sort { $0.2 < $1.2 }
        for f in files where total > maxBytes {
            try? FileManager.default.removeItem(at: f.0)
            total -= f.1
        }
    }

    static func clear() {
        images.removeAllObjects()
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}

/// 가로를 꽉 채우고 세로는 그림 비율대로 (너무 긴 그림은 잘라서)
struct RemoteImage: View {
    let url: String
    var onFail: () -> Void = {}
    @State private var image: UIImage?

    var body: some View {
        let ratio = image.map { min(1.6, max(0.45, $0.size.height / max($0.size.width, 1))) } ?? ImageCache.ratio(url) ?? 0.75
        Color(.tertiarySystemFill)
            .aspectRatio(1 / ratio, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                if image == nil { image = ImageCache.image(url) }
                guard image == nil else { return }
                if let img = await ImageCache.load(url) { withAnimation(.easeOut(duration: 0.2)) { image = img } } else { onFail() }
            }
            .accessibilityHidden(true)
    }
}

/// 기기에 저장해 두는 그림 (한 번 받으면 인터넷 없이도 보인다)
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: String
    var onFail: () -> Void = {}
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    @State private var image: UIImage?

    init(url: String, onFail: @escaping () -> Void = {}, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.onFail = onFail
        self.content = content
        self.placeholder = placeholder
        _image = State(initialValue: ImageCache.image(url))
    }

    var body: some View {
        Group {
            if let image { content(Image(uiImage: image)) } else { placeholder() }
        }
        .task(id: url) {
            guard image == nil, !url.isEmpty else { return }
            if let img = await ImageCache.load(url) { image = img } else { onFail() }
        }
    }
}

/// 링크가 열리지 않을 때 붙는 표
struct BrokenBadge: View {
    var body: some View {
        Label("안 열림", systemImage: "link.badge.plus")
            .labelStyle(.titleOnly)
            .font(.caption.weight(.bold)).foregroundStyle(.white)
            .padding(.horizontal, 7).frame(height: 22)
            .background(Color.red.opacity(0.85), in: .rect(cornerRadius: 6))
            .accessibilityLabel("링크가 열리지 않아요")
    }
}

/// 영상은 2초만 소리 없이 반복한다 (웹 LoopClip 과 같은 규칙).
/// 화면에 보일 때만 받아서 틀고, 움직임 줄이기·저전력 모드면 틀지 않는다(그림만).
/// 긴 영상은 앞부분(제목·검은 화면)을 건너뛰고 20% 지점(최대 10초)부터.
struct LoopingClip: View {
    let url: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        PlayerLayerView(player: player)
            .opacity(player == nil ? 0 : 1)
            .task(id: url) { await prepare() }
            .onAppear { if !reduceMotion { player?.play() } }
            .onDisappear { player?.pause() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func prepare() async {
        guard player == nil, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled, let u = URL(string: url) else { return }
        let asset = AVURLAsset(url: u)
        guard let duration = try? await asset.load(.duration), !Task.isCancelled else { return }
        let total = duration.seconds
        let start = total.isFinite && total > 6 ? min(total * 0.2, 10) : 0
        let length = total.isFinite && total > 0 ? min(2, total - start) : 2
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: length, preferredTimescale: 600))
        // 소리 없는 영상이 다른 앱 음악을 멈추지 않게
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        let q = AVQueuePlayer()
        q.isMuted = true
        q.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(asset: asset), timeRange: range)
        player = q
        q.play()
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView() }
    func updateUIView(_ view: PlayerUIView, context: Context) { view.playerLayer.player = player }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("코드로만 만든다") }
    }
}
