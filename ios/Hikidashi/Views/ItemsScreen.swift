import SwiftUI
import HikidashiCore

/// 한 범위(전체, 즐겨찾기, 서랍, 태그)의 항목 목록. 날짜별로 묶고, 목록·카드로 볼 수 있다
struct ItemsScreen: View {
    let scope: Scope
    var onMenu: () -> Void = {}
    @Environment(LibraryStore.self) private var store
    @State private var query = ""
    @AppStorage("viewMode") private var viewMode = "list"

    private var showFolder: Bool {
        if case .folder = scope { return false }
        return true
    }

    var body: some View {
        let items = store.items(in: scope, query: query)
        Group {
            if items.isEmpty {
                empty
            } else if viewMode == "grid" {
                grid(items)
            } else {
                list(items)
            }
        }
        .navigationTitle(store.title(of: scope))
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "제목, 메모, 태그, 주소")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onMenu) { Image(systemName: "sidebar.left") }
                    .accessibilityLabel("서랍 열기")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Picker("보기 방식", selection: $viewMode.animation(.snappy)) {
                    Image(systemName: "list.bullet").accessibilityLabel("목록").tag("list")
                    Image(systemName: "square.grid.2x2").accessibilityLabel("카드").tag("grid")
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
        }
    }

    @ViewBuilder private var empty: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if scope == .starred {
            ContentUnavailableView("즐겨찾기가 없어요", systemImage: "star", description: Text("항목을 오른쪽으로 밀어 즐겨찾기에 넣으세요."))
        } else {
            ContentUnavailableView("비어 있어요", systemImage: "archivebox", description: Text("+ 버튼으로 링크나 메모를 넣어보세요. 위로 끌어 올리면 복사한 링크가 바로 들어가요."))
        }
    }

    private func sections(_ items: [Item]) -> [(Bucket, [Item])] {
        let groups = Dictionary(grouping: items) { store.dates.bucket($0.createdAt) }
        return Bucket.allCases.compactMap { b in groups[b].map { (b, $0) } }
    }

    private func list(_ items: [Item]) -> some View {
        List {
            ForEach(sections(items), id: \.0) { bucket, group in
                Section {
                    ForEach(group) { item in
                        ItemRow(item: item, folder: store.folder(item.folderId), showFolder: showFolder, loading: store.loadingIDs.contains(item.id))
                            .itemActions(item, store: store)
                    }
                } header: {
                    HStack {
                        Text(bucket.rawValue).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                        Spacer()
                        Text("\(group.count)개").font(.footnote).foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                }
            }
            // 떠 있는 + 버튼에 가리지 않게
            Color.clear.frame(height: 72).listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    /// 두 줄 벽돌 쌓기: 그림이 있는 카드는 그림 비율대로 길어지고, 짧은 쪽 줄에 다음 카드를 놓는다
    private func grid(_ items: [Item]) -> some View {
        var cols: [[Item]] = [[], []]
        var heights: [CGFloat] = [0, 0]
        for it in items {
            let c = heights[0] <= heights[1] ? 0 : 1
            cols[c].append(it)
            heights[c] += it.coverImage != nil ? 1 + (ImageCache.ratio(it.coverImage) ?? 0.75) : 0.8
        }
        return ScrollView {
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<2, id: \.self) { c in
                    LazyVStack(spacing: 10) {
                        ForEach(cols[c]) { item in
                            ItemCard(item: item, folder: store.folder(item.folderId), showFolder: showFolder)
                                .itemActions(item, store: store, swipe: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
    }
}

/// 목록 한 줄
struct ItemRow: View {
    let item: Item
    let folder: Folder?
    let showFolder: Bool
    var loading = false
    @Environment(LibraryStore.self) private var store

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ItemIcon(item: item, folder: folder)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle).font(.body.weight(.semibold)).lineLimit(1)
                let sub = item.displaySubtitle
                if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                MetaRow(item: item, folder: folder, showFolder: showFolder).padding(.top, 2)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                if loading { ProgressView().controlSize(.small) }
                if item.starred { Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.star).accessibilityLabel("즐겨찾기") }
                Text(store.dates.stamp(item.createdAt)).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                if item.kind == .memo { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            }
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}

/// 카드 보기 한 칸. 글에 그림이 있으면 그림을 원래 비율대로 크게 보여준다
struct ItemCard: View {
    let item: Item
    let folder: Folder?
    let showFolder: Bool
    @Environment(LibraryStore.self) private var store
    @State private var coverFailed = false

    var body: some View {
        let cover = coverFailed ? nil : item.coverImage
        VStack(alignment: .leading, spacing: 0) {
            if let cover {
                RemoteImage(url: cover, onFail: { coverFailed = true })
                    .overlay(alignment: .topTrailing) { if item.starred { starBadge.padding(8) } }
            }
            VStack(alignment: .leading, spacing: 6) {
                if cover == nil {
                    HStack(alignment: .top) {
                        ItemIcon(item: item, folder: folder, size: 40)
                        Spacer()
                        if item.starred { Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.star) }
                    }
                    .padding(.bottom, 2)
                }
                Text(item.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(cover == nil ? 3 : 2).multilineTextAlignment(.leading)
                let sub = item.displaySubtitle
                if !sub.isEmpty { Text(sub).font(.footnote).foregroundStyle(.secondary).lineLimit(cover == nil ? 4 : 2) }
                // 목록과 같은 줄: 서랍 · 출처 사이트 칩(로고) · 태그
                FlowLayout(spacing: 5) {
                    if showFolder { FolderPill(folder: folder) }
                    if item.kind == .link, let url = item.url { SourceChip(url: url, siteName: item.siteName) }
                    ForEach(item.tags, id: \.self) { t in
                        Text("#\(t)").font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(height: 22)
                    }
                }
                .padding(.top, 2)
                Text(item.kind == .memo ? "메모 · \(store.dates.stamp(item.createdAt))" : store.dates.stamp(item.createdAt))
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.07)))
        .contentShape(.rect(cornerRadius: 18))
    }

    private var starBadge: some View {
        Image(systemName: "star.fill").font(.caption.weight(.bold)).foregroundStyle(Color.star)
            .frame(width: 26, height: 26).background(.regularMaterial, in: .circle)
    }
}

extension Item {
    /// 카드에 크게 보여줄 그림 (프로필 사진처럼 작은 대체 그림은 빼고)
    var coverImage: String? {
        guard kind == .link, let image, !image.isEmpty else { return nil }
        if image.contains("profile_images") { return nil }
        return image
    }
}

extension View {
    /// 누르기, 밀기, 길게 누르기 메뉴를 한곳에서 붙인다
    func itemActions(_ item: Item, store: LibraryStore, swipe: Bool = true) -> some View {
        modifier(ItemActions(item: item, store: store, swipe: swipe))
    }
}

private struct ItemActions: ViewModifier {
    let item: Item
    let store: LibraryStore
    let swipe: Bool

    func body(content: Content) -> some View {
        let base = Button { store.open(item) } label: { content }
            .buttonStyle(.plain)
            .contextMenu {
                Button { store.toggleStar(item) } label: { Label(item.starred ? "즐겨찾기 해제" : "즐겨찾기", systemImage: item.starred ? "star.slash" : "star") }
                Button { store.editor = EditorRequest(editing: item) } label: { Label("편집", systemImage: "pencil") }
                if item.kind == .link {
                    Button { store.copyURL(item) } label: { Label("주소 복사", systemImage: "doc.on.doc") }
                    if let s = item.url, let url = URL(string: s) { ShareLink(item: url) { Label("공유", systemImage: "square.and.arrow.up") } }
                }
                Divider()
                Button(role: .destructive) { store.remove(item) } label: { Label("삭제", systemImage: "trash") }
            }
        if swipe {
            base
                .swipeActions(edge: .leading) {
                    Button { store.toggleStar(item) } label: { Label(item.starred ? "해제" : "즐겨찾기", systemImage: "star") }.tint(.star)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.remove(item) } label: { Label("삭제", systemImage: "trash") }
                    Button { store.editor = EditorRequest(editing: item) } label: { Label("편집", systemImage: "pencil") }.tint(.gray)
                }
        } else {
            base
        }
    }
}
