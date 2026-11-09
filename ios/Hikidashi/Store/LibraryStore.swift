import Foundation
import Observation
import SwiftUI
import UIKit
import HikidashiCore

/// 아래쪽에 잠깐 뜨는 알림. undo 가 있으면 "되돌리기" 버튼이 붙는다
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isError = false
    var undo: (() -> Void)?
    static func == (a: ToastMessage, b: ToastMessage) -> Bool { a.id == b.id }
}

/// 추가·편집 시트를 여는 요청
struct EditorRequest: Identifiable {
    let id = UUID()
    var editing: Item?
    var prefill: ItemDraft?
}

/// 사파리로 열 주소
struct WebPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// 리더 모드로 볼 항목
struct ReaderRequest: Identifiable {
    let item: Item
    var id: String { item.id }
}

/// 앱 전체 상태. 저장은 앱 폴더의 JSON 파일 하나 (백업과 같은 형식이라 그대로 내보낼 수 있다)
@MainActor
@Observable
final class LibraryStore {
    private(set) var library: Library
    var loadingIDs: Set<String> = []
    var toast: ToastMessage?
    var editor: EditorRequest?
    var memoID: String?
    var webPage: WebPage?
    var reader: ReaderRequest?
    /// 오프라인 보기로 연 항목
    var offlineView: OfflineRequest?
    /// 오프라인 저장한 항목 (이 기기에만)
    private(set) var offlineIDs: Set<String> = OfflineDisk.ids
    /// 여러 개 고르는 중이면 고른 항목 id (nil 이면 고르는 중 아님)
    var selection: Set<String>?
    /// 최근에 연 항목 (이 기기에만, 최신이 앞)
    private(set) var recentIDs: [String] = UserDefaults.standard.stringArray(forKey: "recentIDs") ?? []
    private(set) var checkingLinks = false
    /// NSFW 태그가 달린 항목을 보여줄지 (이 기기에만, 기본은 숨김)
    private(set) var showNsfw: Bool = UserDefaults.standard.bool(forKey: "showNsfw")
    /// 아래로 스크롤해서 하단바를 + 버튼으로 접었는지
    var chromeCollapsed = false
    /// 본문 검색용: 저장한 리더 본문 (id → 글, 소문자). 검색을 시작할 때 읽는다
    @ObservationIgnored private var articleTexts: [String: String]?
    /// 동기화 상태 (드롭박스 + 동기화 암호)
    private(set) var syncState: SyncState = .off
    private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    private var syncing = false
    @ObservationIgnored private var syncKey: SyncKey?
    @ObservationIgnored private var syncedSignature = ""
    /// 백그라운드 새로 고침이 쓸 지금 저장소
    static weak var current: LibraryStore?
    private var articles: [String: ReaderArticle] = [:]

    private let fileURL: URL
    private let fetcher = PageInfoFetcher()
    let dates = DateText()

    init(fileURL: URL? = nil, sample: Bool = false) {
        let url = fileURL ?? SharedLibrary.fileURL
        self.fileURL = url
        if sample {
            library = Self.sampleLibrary()
        } else {
            library = SharedLibrary.load(url) ?? .seeded()
        }
        if !sample {
            restoreSyncState()
            Self.current = self
        }
        save()
    }

    private func save(scheduleSync: Bool = true) {
        defer { if scheduleSync { self.scheduleSync() } }
        do { try SharedLibrary.save(library, to: fileURL) } catch { show("저장하지 못했어요: \(error.localizedDescription)", error: true) }
        // 공유 화면에서 고를 수 있게 서랍·태그 목록을 넘겨 둔다
        ShareInbox.writeContext(.init(
            folders: library.liveFolders.map { .init(id: $0.id, name: $0.name, hex: $0.color.hex) },
            tags: Array(library.tagsByUse.prefix(30)),
            defaultFolderId: defaultFolderId
        ))
    }

    /// 앱으로 돌아올 때: 공유 시트로 넣은 항목을 꺼내 기본 서랍에 넣는다
    func drainShareInbox() {
        let entries = ShareInbox.drain()
        guard !entries.isEmpty else { return }
        let fallback = defaultFolderId
        var added = 0
        var newIDs: [String] = []
        change { lib in
            for e in entries {
                if let u = e.draft.url, lib.contains(url: u) { continue }
                let folder: String? = switch e.folderChoice {
                case nil: fallback
                case .some("none"): nil
                case let id?: lib.folder(id) != nil ? id : fallback
                }
                var d = e.draft.draft(folderId: folder)
                d.tags = (e.tags ?? []).map(normalizeTag).filter { !$0.isEmpty }
                newIDs.append(lib.addItem(d, now: e.sharedAt).id)
                added += 1
            }
        }
        if added > 0 { show(added == 1 ? "공유한 항목을 넣었어요" : "공유한 항목 \(added)개를 넣었어요") }
        newIDs.forEach(prefetchArticle)
    }

    /// 새 항목이 들어갈 기본 서랍 (설정에서 고른다)
    var defaultFolderId: String? { SharedLibrary.defaultFolderId(in: library) }

    private func change(_ animated: Bool = true, _ body: (inout Library) -> Void) {
        if animated {
            withAnimation(.snappy(duration: 0.32)) { body(&library) }
        } else {
            body(&library)
        }
        save()
    }

    // MARK: 읽기

    var folders: [Folder] { library.liveFolders }
    /// NSFW 를 숨기면 어디에도 안 나온다
    var allItems: [Item] { showNsfw ? library.liveItems : library.liveItems.filter { !Library.isNsfw($0) } }
    /// 목록에 보이는 항목 (확인 완료한 건 완료함에만)
    var activeItems: [Item] { allItems.filter { $0.doneAt == nil } }
    /// 화면에 보여줄 서랍: 하위 서랍은 이름이 "상위-하위", 색은 상위 것
    func folder(_ id: String?) -> Folder? {
        guard var f = library.folder(id) else { return nil }
        f.name = library.displayName(f)
        f.color = library.displayColor(f)
        f.hex = library.displayHex(f)
        return f
    }
    /// 고르기 목록용: 상위 다음에 하위 (보여줄 이름·색으로)
    var pickFolders: [Folder] { library.orderedFolders.compactMap { folder($0.folder.id) } }
    /// 서랍에 든 항목 수 (상위 서랍은 하위 것까지)
    func count(inFolder id: String) -> Int {
        let fam = library.family(id)
        return activeItems.filter { i in i.folderId.map { fam.contains($0) } ?? false }.count
    }

    /// 저장한 본문을 한 번 읽어 둔다 (검색에서 본문까지 찾게)
    private func articleText(_ id: String) -> String? {
        if articleTexts == nil {
            var m: [String: String] = [:]
            let files = (try? FileManager.default.contentsOfDirectory(atPath: ArticleDisk.folder.path)) ?? []
            for f in files where f.hasSuffix(".json") {
                let id = String(f.dropLast(5))
                if let a = ArticleDisk.load(id) { m[id] = ([a.title ?? ""] + a.blocks.compactMap { ReaderArticle.text(of: $0) }).joined(separator: " ").lowercased() }
            }
            articleTexts = m
        }
        return articleTexts?[id]
    }
    /// 검색이 끝나면 다음 검색 때 새로 읽게
    func forgetArticleTexts() { articleTexts = nil }
    func item(_ id: String?) -> Item? { id.flatMap { library.item($0) }.flatMap { $0.deletedAt == nil ? $0 : nil } }

    func items(in scope: Scope, query: String = "") -> [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var fam: Set<String> = []
        if case .folder(let id) = scope { fam = library.family(id) }
        let source = scope == .done ? allItems.filter { $0.doneAt != nil }.sorted { ($0.doneAt ?? 0) > ($1.doneAt ?? 0) }
            : scope == .highlights ? allItems : activeItems
        return source.filter { i in
            let inScope: Bool
            switch scope {
            case .all, .done: inScope = true
            case .memos: inScope = i.kind == .memo
            case .offline: inScope = offlineIDs.contains(i.id)
            case .starred: inScope = i.starred
            case .unfiled: inScope = library.folder(i.folderId) == nil
            case .folder: inScope = i.folderId.map { fam.contains($0) } ?? false
            case .tag(let t): inScope = i.tags.contains(t)
            case .highlights: inScope = !i.highlights.isEmpty
            case .broken: inScope = i.brokenAt != nil
            }
            guard inScope else { return false }
            guard !q.isEmpty else { return true }
            // 본문 검색: 저장해 둔 리더 본문까지
            let fields = [i.title, i.note, i.url ?? "", domain(of: i.url), i.siteName ?? "", i.tags.joined(separator: " "), i.highlights.joined(separator: " ")]
            return fields.joined(separator: " ").lowercased().contains(q) || (articleText(i.id)?.contains(q) ?? false)
        }
    }

    func title(of scope: Scope) -> String {
        switch scope {
        case .all: "전체"
        case .starred: "즐겨찾기"
        case .unfiled: "미분류"
        case .folder(let id): folder(id)?.name ?? "서랍"
        case .tag(let t): "#\(t)"
        case .highlights: "하이라이트"
        case .broken: "열리지 않는 링크"
        case .done: "완료함"
        case .memos: "메모"
        case .offline: "오프라인"
        }
    }

    // MARK: 알림

    func show(_ text: String, error: Bool = false, undo: (() -> Void)? = nil) {
        let t = ToastMessage(text: text, isError: error, undo: undo)
        withAnimation(.snappy) { toast = t }
        // 잠깐만 보이고 사라진다. 되돌리기가 있으면 누를 시간만큼 조금 더
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 1.6 : 3.5))
            if self?.toast?.id == t.id { withAnimation(.snappy) { self?.toast = nil } }
        }
    }

    // MARK: 항목

    func open(_ item: Item) {
        markOpened(item)
        guard item.kind == .link, let s = item.url, let url = URL(string: s) else { memoID = item.id; return }
        // 설정에서 "리더 모드 먼저" 면 글은 리더로, X·유튜브는 원래 화면으로
        if UserDefaults.standard.string(forKey: "linkOpen") != "safari", supportsReader(s) {
            reader = ReaderRequest(item: item)
        } else {
            webPage = WebPage(url: url)
        }
    }

    /// 오프라인 다운로드 ↔ 저장 지우기. 받으면 원본 글이 지워져도 오프라인 보기로 본다 (영상도 같이)
    func toggleOffline(_ item: Item) {
        if offlineIDs.contains(item.id) { removeOffline(item.id); return }
        loadingIDs.insert(item.id)
        show("오프라인으로 받는 중…")
        Task {
            var article = ArticleDisk.load(item.id)
            if article == nil, item.kind == .link, let url = item.url, supportsReader(url) { article = await fetcher.fetchArticle(url) }
            let pack = await OfflineDisk.download(item, article: article)
            loadingIDs.remove(item.id)
            guard let pack else { return show("오프라인으로 받지 못했어요", error: true) }
            withAnimation(.snappy) { _ = offlineIDs.insert(item.id) }
            show(pack.failed > 0 ? "오프라인 저장함 · 그림·영상 \(pack.failed)개는 받지 못했어요" : pack.media.isEmpty ? "오프라인 저장함" : "오프라인 저장함 · 그림·영상 \(pack.media.count)개")
        }
    }

    func removeOffline(_ id: String) {
        OfflineDisk.remove(id)
        withAnimation(.snappy) { _ = offlineIDs.remove(id) }
        show("오프라인 저장을 지웠어요")
    }

    func openInSafari(_ item: Item) {
        markOpened(item)
        if let s = item.url, let url = URL(string: s) { webPage = WebPage(url: url) }
    }

    private func markOpened(_ item: Item) {
        recentIDs.removeAll { $0 == item.id }
        recentIDs.insert(item.id, at: 0)
        recentIDs = Array(recentIDs.prefix(12))
        UserDefaults.standard.set(recentIDs, forKey: "recentIDs")
    }

    /// 최근 연 항목 (지운 건 빼고)
    var recentItems: [Item] { recentIDs.compactMap { item($0) } }

    /// 리더 본문. 기기에 저장해 둔 게 있으면 그걸, 없으면 받아서 저장한다 (원본이 사라져도 읽게)
    func article(for item: Item) async -> ReaderArticle? {
        if let a = articles[item.id] ?? ArticleDisk.load(item.id) {
            articles[item.id] = a
            return a
        }
        guard let url = item.url, var a = await fetcher.fetchArticle(url) else { return nil }
        a.savedAt = .now
        articles[item.id] = a
        ArticleDisk.save(a, id: item.id)
        return a
    }

    /// 새로 넣은 글은 본문을 미리 받아 둔다 (설정에서 끌 수 있다)
    func prefetchArticle(_ id: String) {
        guard UserDefaults.standard.object(forKey: "saveArticles") as? Bool ?? true,
              let it = item(id), it.kind == .link, supportsReader(it.url), !ArticleDisk.has(id) else { return }
        Task { _ = await article(for: it) }
    }

    func toggleHighlight(_ item: Item, text: String) {
        change(false) { $0.toggleHighlight(item.id, text: text) }
    }

    // MARK: 링크 점검

    var lastLinkCheck: Date? { UserDefaults.standard.object(forKey: "lastLinkCheck") as? Date }

    /// 오래 점검 안 한 링크부터 조금씩 (한 번에 40개, 4개씩 동시에)
    func checkLinks(force: Bool = false) {
        guard !checkingLinks else { return }
        if !force, let last = lastLinkCheck, Date().timeIntervalSince(last) < 86_400 { return }
        let targets = library.liveItems.filter { force ? $0.kind == .link : needsCheck($0) }
            .sorted { ($0.checkedAt ?? 0) < ($1.checkedAt ?? 0) }
            .prefix(force ? 200 : 40)
            .compactMap { it in it.url.map { (it.id, $0) } }
        guard !targets.isEmpty else { return }
        checkingLinks = true
        let before = library.broken.count
        Task {
            let fetcher = self.fetcher
            var results: [(String, LinkHealth)] = []
            await withTaskGroup(of: (String, LinkHealth).self) { group in
                var it = targets.makeIterator()
                for _ in 0..<4 { if case let (id, url)? = it.next() { group.addTask { (id, await fetcher.check(url)) } } }
                for await r in group {
                    results.append(r)
                    if case let (id, url)? = it.next() { group.addTask { (id, await fetcher.check(url)) } }
                }
            }
            change(false) { lib in for (id, h) in results { lib.recordCheck(id, h) } }
            UserDefaults.standard.set(Date(), forKey: "lastLinkCheck")
            checkingLinks = false
            let now = library.broken.count
            if now > before { show("열리지 않는 링크 \(now - before)개를 찾았어요") } else if force { show("링크 \(results.count)개를 점검했어요") }
        }
    }

    // MARK: 여러 개 고르기

    func startSelecting(_ first: Item? = nil) {
        withAnimation(.snappy) { selection = first.map { [$0.id] } ?? [] }
    }

    func stopSelecting() { withAnimation(.snappy) { selection = nil } }

    func toggleSelected(_ item: Item) {
        guard var s = selection else { return }
        if s.contains(item.id) { s.remove(item.id) } else { s.insert(item.id) }
        selection = s
    }

    /// 고른 항목에 한꺼번에 하고, 되돌리기를 띄운다
    private func bulk(_ message: String, _ body: (inout Library, String) -> Void) {
        guard let ids = selection, !ids.isEmpty else { return }
        let before = library
        change { lib in for id in ids { body(&lib, id) } }
        stopSelecting()
        show(message) { [weak self] in self?.change { $0 = before } }
    }

    func moveSelected(to folderId: String?) {
        let n = selection?.count ?? 0
        let name = folder(folderId)?.name ?? "미분류"
        bulk("\(n)개를 ‘\(name)’ 로 옮겼어요") { lib, id in lib.update(id) { $0.folderId = folderId } }
    }

    func tagSelected(_ raw: String) {
        let tags = parseTags(raw.replacingOccurrences(of: " ", with: ","))
        guard !tags.isEmpty else { return }
        let n = selection?.count ?? 0
        bulk("\(n)개에 \(tags.map { "#\($0)" }.joined(separator: " ")) 달았어요") { lib, id in
            lib.update(id) { it in for t in tags where !it.tags.contains(t) { it.tags.append(t) } }
        }
    }

    func starSelected() {
        guard let ids = selection else { return }
        let all = ids.allSatisfy { library.item($0)?.starred == true }
        bulk(all ? "즐겨찾기에서 뺐어요" : "즐겨찾기에 넣었어요") { lib, id in lib.update(id) { $0.starred = !all } }
    }

    func removeSelected() {
        let n = selection?.count ?? 0
        bulk("\(n)개 삭제함") { lib, id in lib.remove(id) }
    }

    func add(_ d: ItemDraft) {
        var id = ""
        change { id = $0.addItem(d).id }
        prefetchArticle(id)
    }
    func apply(_ d: ItemDraft, to id: String) { change { $0.apply(d, to: id) }; show("고쳤어요") }
    func toggleStar(_ item: Item) { change { $0.toggleStar(item.id) } }

    /// 확인 완료 ↔ 완료 취소. 완료하면 목록에서 빠지고 완료함으로
    func toggleDone(_ item: Item) {
        let was = item.doneAt
        let now = Millis.now
        change { $0.update(item.id) { $0.doneAt = was == nil ? now : nil } }
        show(was == nil ? "‘\(item.displayTitle)’ 확인 완료" : "‘\(item.displayTitle)’ 완료 취소") { [weak self] in
            self?.change { $0.update(item.id) { $0.doneAt = was } }
        }
    }

    /// NSFW 항목 보이기 ↔ 숨기기 (이 기기에만)
    func toggleShowNsfw() {
        showNsfw.toggle()
        UserDefaults.standard.set(showNsfw, forKey: "showNsfw")
        show(showNsfw ? "NSFW 항목을 보여줘요" : "NSFW 항목을 숨겼어요")
    }

    /// NSFW 태그 달기 ↔ 빼기
    func toggleNsfw(_ item: Item) {
        let on = !Library.isNsfw(item)
        change { $0.update(item.id) { $0.tags = Library.withNsfw($0.tags, on) } }
        show(on ? (showNsfw ? "NSFW 로 표시했어요" : "NSFW 로 표시해서 숨겼어요") : "NSFW 표시를 뺐어요")
    }

    func doneSelected(undo: Bool) {
        let n = selection?.count ?? 0
        let now = Millis.now
        bulk(undo ? "\(n)개 완료 취소" : "\(n)개 확인 완료") { lib, id in lib.update(id) { $0.doneAt = undo ? nil : now } }
    }

    func remove(_ item: Item) {
        change { $0.remove(item.id) }
        show("‘\(item.displayTitle)’ 삭제함") { [weak self] in self?.change { $0.restore(item.id) } }
    }

    func copyURL(_ item: Item) {
        UIPasteboard.general.string = item.url
        show("주소를 복사했어요")
    }

    // MARK: 서랍

    func addFolder(name: String, color: FolderColor, hex: String? = nil, parentId: String? = nil) { change { $0.addFolder(name: name, color: color, hex: hex, parentId: parentId) }; show("‘\(name)’ 서랍을 만들었어요") }
    func updateFolder(_ id: String, name: String, color: FolderColor, hex: String? = nil, parentId: String?) { change { $0.updateFolder(id, name: name, color: color, hex: hex, parentId: .some(parentId)) } }

    func removeFolder(_ f: Folder) {
        var moved: [String] = []
        change { moved = $0.removeFolder(f.id) }
        show("‘\(f.name)’ 서랍 삭제함") { [weak self] in self?.change { $0.restoreFolder(f.id, moved: moved) } }
    }

    func reorderFolders(_ ids: [String]) { change { $0.reorderFolders(ids) } }

    // MARK: 태그

    func renameTag(_ old: String, to new: String) {
        let before = library
        var n = 0
        change { n = $0.renameTag(old, to: new) }
        guard n > 0 else { return }
        show("#\(old) → #\(normalizeTag(new))") { [weak self] in self?.change { $0 = before } }
    }

    func removeTag(_ tag: String) {
        let before = library
        var n = 0
        change { n = $0.removeTag(tag) }
        guard n > 0 else { return }
        show("#\(tag) 태그를 항목 \(n)개에서 뺐어요") { [weak self] in self?.change { $0 = before } }
    }

    // MARK: 링크 정보

    func fetchInfo(_ url: String) async -> PageInfo? { await fetcher.fetch(url) }

    private var previews: [String: PageInfo] = [:]
    /// 이번 실행에서 프로필 사진을 한 번 찾아본 항목 (실패해도 다시 묻지 않게)
    private var avatarTried: Set<String> = []

    /// 예전에 저장해서 프로필 사진이 없는 X 글: 보일 때 글쓴이 프로필을 받아 채운다 (한 번에 12개까지)
    func fillAvatars(_ items: [Item]) async {
        let need = items.filter { $0.kind == .link && ($0.avatar ?? "").isEmpty && !avatarTried.contains($0.id) && xStatusID($0.url ?? "") != nil }.prefix(12)
        for it in need { avatarTried.insert(it.id) }
        for it in need {
            guard let url = it.url, let info = await fetcher.fetch(url), let avatar = info.avatar else { continue }
            guard let now = library.item(it.id), (now.avatar ?? "").isEmpty else { continue }
            change(false) {
                $0.update(it.id) { x in
                    x.avatar = avatar
                    if x.images.isEmpty { x.images = info.images }
                    if x.video == nil { x.video = info.video }
                    if x.siteName == nil || x.siteName == "X", let s = info.siteName { x.siteName = s }
                    // 예전엔 프로필 사진을 대표 그림 자리에 넣기도 했다
                    if x.image?.contains("profile_images") == true, let img = info.image, !img.contains("profile_images") { x.image = img }
                }
            }
        }
    }

    /// 메모 속 링크 미리보기 (한 번 받은 건 기억)
    func previewInfo(_ url: String) async -> PageInfo? {
        if let p = previews[url] { return p }
        let p = await fetcher.fetch(url)
        if let p { previews[url] = p }
        return p
    }

    /// + 버튼을 끌어올렸다 놓으면: 클립보드 링크를 바로 넣고 정보는 받는 대로 채운다
    func quickAddFromPasteboard(into folder: String? = nil) {
        let folderId = folder ?? defaultFolderId
        guard let text = UIPasteboard.general.string else { return show("복사한 링크가 없어요. 링크를 복사한 뒤 다시 해보세요") }
        guard let url = normalizeURL(text) ?? findURL(in: text) else { return show("복사한 링크가 없어요. 링크를 복사한 뒤 다시 해보세요") }
        if library.contains(url: url) { return show("이미 저장한 링크예요") }
        let id = newID()
        change { $0.addItem(ItemDraft(kind: .link, url: url, folderId: folderId), id: id) }
        loadingIDs.insert(id)
        show("복사한 링크를 추가했어요") { [weak self] in self?.change { $0.remove(id) } }
        Task {
            let info = await fetchInfo(url)
            loadingIDs.remove(id)
            guard let now = library.item(id), now.deletedAt == nil else { return }
            change {
                $0.update(id) { it in
                    // 그사이 사용자가 고친 칸은 건드리지 않는다
                    if it.title.isEmpty, let t = info?.title { it.title = t }
                    if it.note.isEmpty, let d = info?.description { it.note = d }
                    if it.image == nil { it.image = info?.image }
                    if it.video == nil { it.video = info?.video }
                    if it.avatar == nil { it.avatar = info?.avatar }
                    if it.images.isEmpty { it.images = info?.images ?? [] }
                    if it.siteName == nil { it.siteName = info?.siteName }
                    if info == nil, it.title.isEmpty, it.note.isEmpty { it.title = guessTitle(url) }
                }
            }
            prefetchArticle(id)
        }
    }

    // MARK: 백업

    func writeBackupFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Backup.fileName())
        try library.backup().encoded().write(to: url, options: .atomic)
        return url
    }

    func importBackup(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let b = try parseBackup(try Data(contentsOf: url))
            var r = (items: 0, folders: 0)
            change { r = $0.importBackup(b) }
            show(r.items + r.folders > 0 ? "항목 \(r.items)개, 서랍 \(r.folders)개를 가져왔어요" : "새로 가져올 내용이 없어요. 이미 최신이에요")
        } catch {
            show((error as? LocalizedError)?.errorDescription ?? "백업을 가져오지 못했어요", error: true)
        }
    }

    // MARK: 화면 테스트용 예시

    static func sampleLibrary() -> Library {
        var lib = Library.seeded(now: .now - 30 * 86_400_000)
        let f = lib.liveFolders
        let day: Millis = 86_400_000
        let now = Millis.now
        lib.addItem(ItemDraft(kind: .link, url: "https://developer.mozilla.org/ko/docs/Web/CSS/CSS_grid_layout", title: "CSS 그리드 레이아웃", note: "그리드 컨테이너, 트랙, 영역까지 한 번에 정리된 문서", siteName: "MDN Web Docs", folderId: f[1].id, tags: ["css", "참고"]), now: now - 600_000)
        lib.addItem(ItemDraft(kind: .memo, title: "장보기", note: "계란 / 대파 / 버터\n신김치", emoji: "🛒", folderId: f[2].id, tags: ["마트"]), now: now - 3_600_000)
        lib.addItem(ItemDraft(kind: .link, url: "https://x.com/elonmusk/status/1585341984679469056", note: "Entering Twitter HQ – let that sink in!", siteName: "X · @elonmusk", folderId: f[0].id), now: now - day)
        lib.addItem(ItemDraft(kind: .link, url: "https://www.youtube.com/watch?v=jNQXAC9IVRw", title: "Me at the zoo", image: "https://i.ytimg.com/vi/jNQXAC9IVRw/hqdefault.jpg", siteName: "YouTube", folderId: f[0].id, tags: ["영상"]), now: now - 3 * day)
        lib.addItem(ItemDraft(kind: .memo, title: "오사카 메모", note: "도톤보리 → 쿠로몬 시장은 아침에\n영상 참고 https://www.youtube.com/watch?v=jNQXAC9IVRw", emoji: "✈️", tags: ["여행"]), now: now - 12 * day)
        if let star = lib.liveItems.first(where: { $0.kind == .memo }) { lib.toggleStar(star.id) }
        if let css = lib.liveItems.first(where: { $0.title == "CSS 그리드 레이아웃" }) {
            lib.toggleHighlight(css.id, text: "CSS 그리드 레이아웃은 페이지를 여러 주요 영역으로 나누거나, 요소 간의 관계를 정의하는 데 탁월합니다.")
        }
        return lib
    }
}

/// 리더 본문을 기기에 저장해 둔다 (Application Support/articles/항목id.json). 동기화하지 않는다
enum ArticleDisk {
    static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("articles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func file(_ id: String) -> URL { folder.appendingPathComponent(id + ".json") }
    static func has(_ id: String) -> Bool { FileManager.default.fileExists(atPath: file(id).path) }
    static func load(_ id: String) -> ReaderArticle? { (try? Data(contentsOf: file(id))).flatMap { try? JSONDecoder().decode(ReaderArticle.self, from: $0) } }
    static func save(_ a: ReaderArticle, id: String) { (try? JSONEncoder().encode(a)).map { try? $0.write(to: file(id), options: .atomic) } }

    static var count: Int { (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count) ?? 0 }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}

// MARK: - 동기화: 드롭박스 앱 폴더의 잠근 파일 하나 (웹앱과 같은 규칙, docs/SPEC.md 동기화)

enum SyncState: Equatable {
    /// 이 빌드엔 드롭박스 앱 키가 없다
    case unset
    case off
    /// 동기화 암호가 필요하다. fresh 면 드롭박스에 파일이 아직 없어 새로 정한다
    case needsKey(fresh: Bool, note: String?)
    case idle(last: Date?)
    case syncing
    case failed(message: String)

    /// 암호까지 넣어 맞출 수 있는 상태
    var ready: Bool {
        switch self {
        case .idle, .syncing, .failed: true
        default: false
        }
    }
}

extension LibraryStore {
    private static let revKey = "syncRev"
    private static let lastKey = "lastSyncAt"

    /// 데이터가 바뀌었는지 가볍게 보는 표시 (웹과 같은 방식)
    private var signature: String {
        let maxF = library.folders.map(\.updatedAt).max() ?? 0
        let maxI = library.items.map(\.updatedAt).max() ?? 0
        return "\(library.items.count):\(library.folders.count):\(max(maxF, maxI))"
    }

    /// 앱을 켤 때 상태를 채운다
    func restoreSyncState() {
        // 예전 iCloud Drive 폴더 방식의 흔적은 지운다
        UserDefaults.standard.removeObject(forKey: "syncFolderBookmark")
        let box = Dropbox.shared
        guard box.configured else { syncState = .unset; return }
        guard box.isConnected else { syncState = .off; return }
        if let d = SyncKeychain.read(.vaultKey), let key = try? JSONDecoder().decode(SyncKey.self, from: d) {
            syncKey = key
            syncState = .idle(last: UserDefaults.standard.object(forKey: Self.lastKey) as? Date)
        } else {
            syncState = .needsKey(fresh: false, note: nil)
            Task { await refreshFresh() }
        }
    }

    /// 암호를 정해야 하는지(드롭박스에 파일이 없는지) 확인
    private func refreshFresh() async {
        guard case .needsKey(_, let note) = syncState else { return }
        do {
            let rev = try await Dropbox.shared.rev()
            syncState = .needsKey(fresh: rev == nil, note: note)
        } catch {}
    }

    /// 설정에서 "드롭박스로 동기화"
    func connectDropbox() async {
        do {
            try await Dropbox.shared.login()
            syncState = .needsKey(fresh: false, note: nil)
            await refreshFresh()
        } catch Dropbox.Failure.cancelled {
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    /// 동기화 암호를 받았을 때. 파일이 있으면 그 암호로 열리는지 확인하고, 없으면 새로 정한다. 안 되면 이유를 돌려준다
    func submitPassphrase(_ pass: String) async -> String? {
        do {
            let got = try await Dropbox.shared.read()
            let env = try got.map { try SyncEnvelope.decode($0.data) }
            let kdf = env?.kdf ?? SyncVault.newKdf()
            let key = try await Task.detached(priority: .userInitiated) { try SyncVault.deriveKey(passphrase: pass, kdf: kdf) }.value
            if let env { _ = try SyncVault.open(env, with: key) }
            clearSyncProgress()
            SyncKeychain.write(.vaultKey, try JSONEncoder().encode(key))
            syncKey = key
            syncState = .idle(last: nil)
            await syncNow(quiet: false)
            startLiveSync()
            return nil
        } catch SyncVaultError.wrongPassphrase {
            return "암호가 맞지 않아요"
        } catch Dropbox.Failure.notConnected {
            syncState = .off
            return Dropbox.Failure.notConnected.localizedDescription
        } catch {
            return error.localizedDescription
        }
    }

    func disconnectSync() {
        stopLiveSync()
        syncTask?.cancel()
        Task { await Dropbox.shared.disconnect() }
        clearSyncProgress()
        SyncKeychain.delete(.vaultKey)
        syncKey = nil
        UserDefaults.standard.removeObject(forKey: Self.lastKey)
        syncState = .off
    }

    private func clearSyncProgress() {
        UserDefaults.standard.removeObject(forKey: Self.revKey)
        syncedSignature = ""
    }

    /// 고친 뒤 잠깐 기다렸다가 (여러 번 고쳐도 한 번만)
    func scheduleSync() {
        guard syncState.ready, !syncing else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    /// 받기 → 풀기 → 합치기 → 이 기기에 더 새것이 있으면 잠가서 올리기
    func syncNow(quiet: Bool = true) async {
        guard !syncing, syncState.ready, let key = syncKey else { return }
        syncing = true
        syncState = .syncing
        defer { syncing = false }
        let d = UserDefaults.standard
        do {
            let box = Dropbox.shared
            var changed = 0
            var newRev: String?
            let dirty = signature != syncedSignature
            if let last = d.string(forKey: Self.revKey), !dirty, try await box.rev() == last {
                newRev = last // 양쪽 다 그대로
            } else {
                for round in 0..<3 {
                    let got = try await box.read()
                    var theirs: Backup?
                    if let got {
                        let plain = try SyncVault.open(try SyncEnvelope.decode(got.data), with: key)
                        let b = try parseBackup(plain)
                        var merged = library
                        let r = merged.importBackup(b)
                        if r.items + r.folders > 0 {
                            withAnimation(.snappy) { library = merged }
                            save(scheduleSync: false)
                            changed += r.items + r.folders
                        }
                        theirs = b
                    }
                    if let got, let theirs, !hasNewer(folders: library.folders, items: library.items, than: theirs) {
                        newRev = got.rev
                        break
                    }
                    let sealed = try SyncVault.seal(try library.backup().encoded(), with: key)
                    if let rev = try await box.write(sealed, rev: got?.rev) { newRev = rev; break }
                    if round == 2 { throw Dropbox.Failure.server("다른 기기와 동시에 고치고 있어요. 잠시 뒤에 다시 해주세요") }
                }
            }
            d.set(newRev, forKey: Self.revKey)
            syncedSignature = signature
            let now = Date()
            d.set(now, forKey: Self.lastKey)
            syncState = .idle(last: now)
            if !quiet || changed > 0 { show(changed > 0 ? "다른 기기에서 \(changed)개를 가져왔어요" : "동기화했어요") }
        } catch SyncVaultError.wrongPassphrase {
            stopLiveSync()
            SyncKeychain.delete(.vaultKey)
            syncKey = nil
            clearSyncProgress()
            syncState = .needsKey(fresh: false, note: "다른 기기에서 동기화 암호를 바꿨어요. 새 암호를 넣어주세요")
        } catch Dropbox.Failure.notConnected {
            stopLiveSync()
            SyncKeychain.delete(.vaultKey)
            syncKey = nil
            clearSyncProgress()
            syncState = .off
            show(Dropbox.Failure.notConnected.localizedDescription, error: true)
        } catch {
            syncState = .failed(message: error.localizedDescription)
            if !quiet { show("동기화하지 못했어요", error: true) }
        }
    }

    // MARK: 열려 있는 동안 바로 받기 (드롭박스 롱폴링)

    func startLiveSync() {
        guard liveTask == nil, syncState.ready else { return }
        liveTask = Task { [weak self] in
            var cursor: String?
            while !Task.isCancelled {
                do {
                    if cursor == nil { cursor = try await Dropbox.shared.latestCursor() }
                    let r = try await Dropbox.shared.waitForChange(cursor: cursor!)
                    if Task.isCancelled { break }
                    if r.changes {
                        cursor = try await Dropbox.shared.advance(cursor: cursor!)
                        await self?.syncNow()
                    }
                    if let b = r.backoff { try await Task.sleep(for: .seconds(b)) }
                } catch {
                    if Task.isCancelled { break }
                    cursor = nil
                    try? await Task.sleep(for: .seconds(30))
                }
                if self?.syncState.ready != true { break }
            }
        }
    }

    func stopLiveSync() {
        liveTask?.cancel()
        liveTask = nil
    }
}
