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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Color.clear.onAppear { imageFailed = true }
                    default: Color(.secondarySystemFill)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: corner))
                .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(.primary.opacity(0.08)))
            } else if item.kind == .link, !logoFailed, let logo = logoURL(item.url, size: 128).flatMap(URL.init(string:)) {
                AsyncImage(url: logo) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit().padding(size * 0.2)
                    case .failure: Color.clear.onAppear { logoFailed = true }
                    default: Color.clear
                    }
                }
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
            AsyncImage(url: logoURL(url, size: 32).flatMap(URL.init(string:))) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFit() } else {
                    Text(host.prefix(1).uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(Color.secondary, in: .rect(cornerRadius: 3))
                }
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
            let size = s.sizeThatFits(.unspecified)
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
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
