import SwiftUI
import HikidashiCore

/// 한 범위(전체, 즐겨찾기, 서랍, 태그)의 항목 목록. 날짜별로 묶고, 목록·카드로 볼 수 있다
struct ItemsScreen: View {
    let scope: Scope
    var onMenu: () -> Void = {}
    @Environment(LibraryStore.self) private var store
    @State private var query = ""
    @State private var tagging = false
    @State private var tagText = ""
    @AppStorage("viewMode") private var viewMode = "list"
    @AppStorage("groupBy") private var groupBy = "day"

    private var showFolder: Bool {
        // 상위 서랍을 볼 땐 어느 하위 서랍 것인지 칩으로 보여준다
        if case .folder(let id) = scope { return store.library.family(id).count > 1 }
        return true
    }

    var body: some View {
        let items = store.items(in: scope, query: query)
        Group {
            if items.isEmpty {
                empty
            } else if scope == .highlights {
                HighlightsList(items: items.sorted { $0.updatedAt > $1.updatedAt })
            } else if viewMode == "grid" {
                grid(items)
            } else {
                list(items)
            }
        }
        .navigationTitle(store.selection.map { $0.isEmpty ? "항목 고르기" : "\($0.count)개 선택" } ?? store.title(of: scope))
        // 큰 제목을 버튼 줄과 같은 높이에 둬서 제목 위아래 빈 공간을 맞춘다
        .toolbarTitleDisplayMode(.inlineLarge)
        // 검색창은 평소엔 숨기고, 목록을 아래로 당기면 나온다
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "제목, 메모, 태그, 주소, 본문")
        .onChange(of: query) { _, q in if q.isEmpty { store.forgetArticleTexts() } }
        .toolbar {
            if let sel = store.selection {
                ToolbarItem(placement: .topBarLeading) {
                    Button("완료") { store.stopSelecting() }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let all = Set(items.map(\.id))
                    Button(sel == all && !all.isEmpty ? "선택 해제" : "모두 선택") {
                        store.selection = sel == all ? [] : all
                    }
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onMenu) { Image(systemName: "sidebar.left") }
                        .accessibilityLabel("서랍 열기")
                }
                // 두 버튼을 한 묶음에 넣으면 iOS 26 의 유리 배경 안에서 세그먼트가 겹쳐 보여서 따로 둔다
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.startSelecting() } label: { Image(systemName: "checkmark.circle") }
                        .accessibilityLabel("여러 개 고르기")
                        .disabled(items.isEmpty)
                }

            }
        }
        .safeAreaInset(edge: .bottom) {
            if let sel = store.selection {
                selectionBar(sel).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("태그 달기", isPresented: $tagging) {
            TextField("태그 (띄어 쓰면 여러 개)", text: $tagText).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("달기") { store.tagSelected(tagText); tagText = "" }
            Button("취소", role: .cancel) { tagText = "" }
        } message: { Text("고른 항목에 태그를 더해요. 이미 있는 태그는 그대로예요.") }
    }

    /// 고르는 중일 때 아래에 뜨는 버튼 줄: 옮기기, 태그, 즐겨찾기, 삭제
    private func selectionBar(_ sel: Set<String>) -> some View {
        let none = sel.isEmpty
        return HStack(spacing: 0) {
            Menu {
                ForEach(store.pickFolders) { f in
                    Button { store.moveSelected(to: f.id) } label: { Label(f.name, systemImage: "folder.fill") }
                }
                Button { store.moveSelected(to: nil) } label: { Label("미분류", systemImage: "archivebox") }
            } label: { barLabel("옮기기", "folder") }
            Button { tagging = true } label: { barLabel("태그", "number") }
            Button { store.starSelected() } label: { barLabel("즐겨찾기", "star") }
            Button { store.doneSelected(undo: scope == .done) } label: { barLabel(scope == .done ? "완료 취소" : "완료", "checkmark.circle") }
            Button(role: .destructive) { store.removeSelected() } label: { barLabel("삭제", "trash").foregroundStyle(none ? Color.secondary : Color.red) }
        }
        .disabled(none)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .modifier(GlassCapsule())
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func barLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
            Text(title).font(.caption2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(.rect)
    }

    @ViewBuilder private var empty: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if scope == .highlights {
            ContentUnavailableView("하이라이트가 없어요", systemImage: "highlighter", description: Text("리더 모드에서 문단을 길게 눌러 형광펜을 칠해보세요."))
        } else if scope == .broken {
            ContentUnavailableView("모두 잘 열려요", systemImage: "checkmark.seal", description: Text("열리지 않는 링크가 생기면 여기에 모여요."))
        } else if scope == .done {
            ContentUnavailableView("완료한 항목이 없어요", systemImage: "checkmark.circle", description: Text("항목을 길게 눌러 ‘확인 완료’ 하면 목록에서 빠지고 여기로 와요."))
        } else if scope == .starred {
            ContentUnavailableView("즐겨찾기가 없어요", systemImage: "star", description: Text("항목을 오른쪽으로 밀어 즐겨찾기에 넣으세요."))
        } else {
            ContentUnavailableView("비어 있어요", systemImage: "archivebox", description: Text("+ 버튼으로 링크나 메모를 넣어보세요. 위로 끌어 올리면 복사한 링크가 바로 들어가요."))
        }
    }

    /// 목록 묶음: 날짜별(오늘·어제…) 또는 사이트별(많은 사이트부터, 메모는 맨 뒤)
    private func sections(_ items: [Item]) -> [(String, [Item])] {
        if groupBy == "site" && scope != .done {
            let groups = Dictionary(grouping: items) { $0.kind == .memo ? "" : siteKey($0) }
            return groups.sorted { a, b in
                if a.key.isEmpty != b.key.isEmpty { return b.key.isEmpty }
                return a.value.count != b.value.count ? a.value.count > b.value.count : a.key.localizedStandardCompare(b.key) == .orderedAscending
            }.map { ($0.key.isEmpty ? "메모" : $0.key, $0.value) }
        }
        let groups = Dictionary(grouping: items) { store.dates.bucket($0.createdAt) }
        return Bucket.allCases.compactMap { b in groups[b].map { (b.rawValue, $0) } }
    }

    /// 사이트 이름: 출처 칩과 같게 (X 는 계정과 상관없이 X 하나로)
    private func siteKey(_ i: Item) -> String {
        if let s = i.siteName, !s.isEmpty { return s.hasPrefix("X · ") ? "X" : s }
        let d = domain(of: i.url)
        return d.isEmpty ? "알 수 없음" : d
    }

    private func list(_ items: [Item]) -> some View {
        List {
            ForEach(sections(items), id: \.0) { bucket, group in
                Section {
                    ForEach(group) { item in
                        // 홈은 타임라인, 리스트는 한 줄씩
                        if viewMode == "rows" {
                            ItemRow(item: item, folder: store.folder(item.folderId), showFolder: showFolder, loading: store.loadingIDs.contains(item.id), selected: store.selection.map { $0.contains(item.id) })
                                .itemActions(item, store: store)
                        } else {
                            TimelineRow(item: item, folder: store.folder(item.folderId), showFolder: showFolder, loading: store.loadingIDs.contains(item.id), selected: store.selection.map { $0.contains(item.id) })
                                .itemActions(item, store: store)
                        }
                    }
                } header: {
                    HStack {
                        Text(bucket).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
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
        .modifier(CollapseOnScroll())
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
                            ItemCard(item: item, folder: store.folder(item.folderId), showFolder: showFolder, selected: store.selection.map { $0.contains(item.id) })
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
        .modifier(CollapseOnScroll())
    }
}

/// 목록 한 줄
struct ItemRow: View {
    let item: Item
    let folder: Folder?
    let showFolder: Bool
    var loading = false
    /// nil: 고르는 중 아님
    var selected: Bool? = nil
    @Environment(LibraryStore.self) private var store

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let selected { SelectMark(on: selected).transition(.move(edge: .leading).combined(with: .opacity)) }
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
    var selected: Bool? = nil
    @Environment(LibraryStore.self) private var store
    @State private var coverFailed = false

    var body: some View {
        let clip = item.coverVideo
        let cover = coverFailed ? nil : item.coverImage
        VStack(alignment: .leading, spacing: 0) {
            if let clip {
                // 영상은 2초만 소리 없이 반복 (그림이 있으면 받는 동안 그림을 먼저)
                Group {
                    if let cover {
                        RemoteImage(url: cover, onFail: { coverFailed = true }).overlay { LoopingClip(url: clip) }
                    } else {
                        Color(.tertiarySystemFill).aspectRatio(16 / 9, contentMode: .fit).overlay { LoopingClip(url: clip) }
                    }
                }
                .clipped()
                .overlay(alignment: .topTrailing) { if item.starred { starBadge.padding(8) } }
            } else if let cover {
                RemoteImage(url: cover, onFail: { coverFailed = true })
                    .overlay(alignment: .topTrailing) { if item.starred { starBadge.padding(8) } }
            }
            VStack(alignment: .leading, spacing: 6) {
                if cover == nil && clip == nil {
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
                    if item.brokenAt != nil { BrokenBadge() }
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
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected == true ? Color.brand : .primary.opacity(0.07), lineWidth: selected == true ? 2.5 : 1))
        .overlay(alignment: .topLeading) { if let selected { SelectMark(on: selected).padding(8) } }
        .scaleEffect(selected == true ? 0.97 : 1)
        .contentShape(.rect(cornerRadius: 18))
    }

    private var starBadge: some View {
        Image(systemName: "star.fill").font(.caption.weight(.bold)).foregroundStyle(Color.star)
            .frame(width: 26, height: 26).background(.regularMaterial, in: .circle)
    }
}

extension Item {
    /// 카드에서 반복 재생할 영상
    var coverVideo: String? {
        guard kind == .link, emoji == nil, let video, !video.isEmpty else { return nil }
        return video
    }

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
        if store.selection != nil {
            // 고르는 중엔 누르면 고르기만
            Button { withAnimation(.snappy(duration: 0.2)) { store.toggleSelected(item) } } label: { content }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: store.selection?.contains(item.id))
        } else {
            normal(content)
        }
    }

    @ViewBuilder private func normal(_ content: Content) -> some View {
        let base = Button { store.open(item) } label: { content }
            .buttonStyle(.plain)
            .contextMenu {
                Button { store.toggleStar(item) } label: { Label(item.starred ? "즐겨찾기 해제" : "즐겨찾기", systemImage: item.starred ? "star.slash" : "star") }
                Button { store.editor = EditorRequest(editing: item) } label: { Label("편집", systemImage: "pencil") }
                Button { store.toggleDone(item) } label: {
                    Label(item.doneAt == nil ? "확인 완료" : "완료 취소", systemImage: item.doneAt == nil ? "checkmark.circle" : "arrow.uturn.backward")
                }
                Button { store.startSelecting(item) } label: { Label("여러 개 고르기", systemImage: "checkmark.circle") }
                if item.kind == .link {
                    if supportsReader(item.url) {
                        Button { store.reader = ReaderRequest(item: item) } label: { Label("리더로 보기", systemImage: "doc.plaintext") }
                    }
                    Button { store.openInSafari(item) } label: { Label("사파리로 열기", systemImage: "safari") }
                    Button { store.copyURL(item) } label: { Label("주소 복사", systemImage: "doc.on.doc") }
                    if let s = item.url, let url = URL(string: s) { ShareLink(item: url) { Label("공유", systemImage: "square.and.arrow.up") } }
                }
                Button { store.toggleNsfw(item) } label: {
                    Label(Library.isNsfw(item) ? "NSFW 표시 빼기" : "NSFW 로 표시", systemImage: "eye.slash")
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

/// 고르기 동그라미
struct SelectMark: View {
    let on: Bool
    var body: some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(on ? Color.brand : Color.secondary)
            .background(Circle().fill(Color(.systemBackground)).padding(2))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(on ? "선택됨" : "선택 안 됨")
    }
}
