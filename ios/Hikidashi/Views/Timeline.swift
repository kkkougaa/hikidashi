import SwiftUI
import HikidashiCore

/// 타임라인 보기 한 줄 (웹 TimelineRow 와 같은 규칙): 동그란 사진 · 이름 · 사이트 · 시간 / 내용 그대로 / 사진·영상
struct TimelineRow: View {
    let item: Item
    let folder: Folder?
    let showFolder: Bool
    var loading = false
    /// nil: 고르는 중 아님
    var selected: Bool? = nil
    @Environment(LibraryStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let selected {
                SelectMark(on: selected).frame(width: 44)
            } else {
                TimelineAvatar(item: item, folder: folder)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(item.timelineName).font(.subheadline.weight(.bold)).lineLimit(1).layoutPriority(2)
                    Text(item.timelineHandle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text("· \(store.dates.stamp(item.createdAt))").font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    if loading { ProgressView().controlSize(.small) }
                    if item.starred { Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.star).accessibilityLabel("즐겨찾기") }
                }
                let text = item.timelineText
                if !text.isEmpty { Text(text).font(.subheadline).lineLimit(10).fixedSize(horizontal: false, vertical: true) }
                TimelineMedia(item: item)
                MetaRow(item: item, folder: folder, showFolder: showFolder).padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

/// 동그란 사진: 고른 이모지·메모 → SNS 프로필 → 사이트 파비콘
struct TimelineAvatar: View {
    let item: Item
    let folder: Folder?
    @State private var step = 0

    private var sources: [String] {
        guard item.kind == .link, item.emoji == nil else { return [] }
        let old = item.image.flatMap { $0.contains("profile_images") ? $0 : nil }
        return [item.avatar, old, logoURL(item.url, size: 128)].compactMap { $0 }
    }

    var body: some View {
        let list = sources
        Group {
            if step < list.count {
                let src = list[step]
                let isLogo = src == logoURL(item.url, size: 128)
                CachedImage(url: src, onFail: { step += 1 }) { img in
                    if isLogo {
                        img.resizable().scaledToFit().frame(width: 26, height: 26)
                            .frame(width: 44, height: 44).background(Color.white)
                    } else {
                        img.resizable().scaledToFill()
                    }
                } placeholder: {
                    Color(.tertiarySystemFill)
                }
                .id(src)
            } else {
                ItemIcon(item: item, folder: folder, size: 44)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.primary.opacity(0.06)))
        .accessibilityHidden(true)
    }
}

/// X 처럼: 사진 여러 장은 격자, 영상은 2초 반복, 아니면 대표 그림 한 장
struct TimelineMedia: View {
    let item: Item

    var body: some View {
        if item.kind == .link, item.emoji == nil {
            if let clip = item.coverVideo {
                Color(.tertiarySystemFill)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if let cover = item.coverImage { CachedImage(url: cover) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
                        LoopingClip(url: clip)
                    }
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            } else if item.images.count > 1 {
                grid(Array(item.images.prefix(4)))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            } else if let cover = item.coverImage {
                // 한 장은 자르지 않고 원래 비율대로 (세로로 긴 건 높이를 넘지 않게 줄여서 가운데)
                CachedImage(url: cover) { img in
                    img.resizable().scaledToFit()
                        .frame(maxHeight: 560)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.08)))
                        .frame(maxWidth: .infinity)
                } placeholder: {
                    Color(.tertiarySystemFill).aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder private func grid(_ urls: [String]) -> some View {
        let gap: CGFloat = 2
        switch urls.count {
        case 2:
            HStack(spacing: gap) { cell(urls[0]); cell(urls[1]) }
        case 3:
            HStack(spacing: gap) {
                cell(urls[0])
                VStack(spacing: gap) { cell(urls[1]); cell(urls[2]) }
            }
        default:
            VStack(spacing: gap) {
                HStack(spacing: gap) { cell(urls[0]); cell(urls[1]) }
                HStack(spacing: gap) { cell(urls[2]); cell(urls[3]) }
            }
        }
    }

    private func cell(_ url: String) -> some View {
        Color(.tertiarySystemFill)
            .overlay { CachedImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
            .clipped()
    }
}

extension Item {
    private var isX: Bool { siteName?.hasPrefix("X · ") == true }
    /// 이름 자리: 제목 (X 게시물처럼 제목이 없으면 @아이디)
    var timelineName: String {
        if !title.isEmpty { return title }
        if isX, let s = siteName { return String(s.dropFirst(4)) }
        return displayTitle
    }
    /// 이름 옆 작은 글씨: 사이트
    var timelineHandle: String {
        if kind == .memo { return "메모" }
        if isX { return "X" }
        if let s = siteName, !s.isEmpty { return s }
        return domain(of: url)
    }
    /// 본문: 내용 그대로 (제목이 첫 줄을 빌려 썼으면 그 줄은 빼고)
    var timelineText: String {
        if !title.isEmpty || isX { return note.trimmingCharacters(in: .whitespacesAndNewlines) }
        return note.split(whereSeparator: \.isNewline).dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 하단바: 타임라인 · 미디어 · 설정. + 버튼과 떨어진 리퀴드 글래스.
/// 아래로 스크롤하면 + 버튼 쪽으로 쫀득하게 빨려 들어가고, 위로 올리면 다시 나온다
struct DockBar: View {
    @Binding var viewMode: String
    var collapsed: Bool
    var onSettings: () -> Void
    var onReselect: () -> Void = {}

    var body: some View {
        HStack(spacing: 2) {
            tab("홈", "house", on: viewMode == "list") { pick("list") }
            tab("리스트", "list.bullet.rectangle", on: viewMode == "rows") { pick("rows") }
            tab("그리드", "square.grid.2x2", on: viewMode == "grid") { pick("grid") }
            tab("설정", "gearshape", on: false, action: onSettings)
        }
        .padding(5)
        .frame(height: 60)
        .background { glass }
        .sensoryFeedback(.selection, trigger: viewMode)
    }

    private func pick(_ mode: String) {
        if viewMode == mode { onReselect() } else { withAnimation(.snappy) { viewMode = mode } }
    }

    private func tab(_ title: String, _ icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // 글씨 없이 아이콘만 (읽어 주는 이름은 accessibilityLabel)
            Image(systemName: on ? "\(icon).fill" : icon).font(.system(size: 21, weight: .semibold))
            .foregroundStyle(on ? Color.brand : .secondary)
            .frame(minWidth: 58, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .background(on ? Color.primary.opacity(0.07) : .clear, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var glass: some View {
        let shape = Capsule(style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.interactive(), in: shape)
        } else {
            fallback(shape)
        }
        #else
        fallback(shape)
        #endif
    }

    private func fallback(_ shape: Capsule) -> some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
    }
}

/// 아래로 스크롤하면 하단바를 접고, 위로 올리거나 맨 위면 펼친다 (iOS 18 부터. 그 전엔 늘 펼쳐 둔다)
struct CollapseOnScroll: ViewModifier {
    @Environment(LibraryStore.self) private var store

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { old, new in
                let d = new - old
                guard abs(d) > 4 else { return }
                let c = d > 0 && new > 40
                if c != store.chromeCollapsed {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { store.chromeCollapsed = c }
                }
            }
        } else {
            content
        }
    }
}
