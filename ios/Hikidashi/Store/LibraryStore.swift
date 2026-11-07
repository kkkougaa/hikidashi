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
        save()
    }

    private func save() {
        do { try SharedLibrary.save(library, to: fileURL) } catch { show("저장하지 못했어요: \(error.localizedDescription)", error: true) }
    }

    /// 앱으로 돌아올 때: 공유 확장이 그사이 넣은 항목을 합친다 (더 최근에 고친 쪽이 남는다)
    func reloadFromDisk() {
        guard let disk = SharedLibrary.load(fileURL) else { return }
        var merged = library
        let r = merged.importBackup(disk.backup())
        guard r.items + r.folders > 0 else { return }
        withAnimation(.snappy) { library = merged }
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
    var allItems: [Item] { library.liveItems }
    func folder(_ id: String?) -> Folder? { library.folder(id) }
    func item(_ id: String?) -> Item? { id.flatMap { library.item($0) }.flatMap { $0.deletedAt == nil ? $0 : nil } }

    func items(in scope: Scope, query: String = "") -> [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return library.liveItems.filter { i in
            let inScope: Bool
            switch scope {
            case .all: inScope = true
            case .starred: inScope = i.starred
            case .unfiled: inScope = library.folder(i.folderId) == nil
            case .folder(let id): inScope = i.folderId == id
            case .tag(let t): inScope = i.tags.contains(t)
            }
            guard inScope else { return false }
            guard !q.isEmpty else { return true }
            return [i.title, i.note, i.url ?? "", domain(of: i.url), i.tags.joined(separator: " ")].joined(separator: " ").lowercased().contains(q)
        }
    }

    func title(of scope: Scope) -> String {
        switch scope {
        case .all: "전체"
        case .starred: "즐겨찾기"
        case .unfiled: "미분류"
        case .folder(let id): folder(id)?.name ?? "서랍"
        case .tag(let t): "#\(t)"
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
        if item.kind == .link, let s = item.url, let url = URL(string: s) { webPage = WebPage(url: url) } else { memoID = item.id }
    }

    func add(_ d: ItemDraft) { change { $0.addItem(d) } }
    func apply(_ d: ItemDraft, to id: String) { change { $0.apply(d, to: id) }; show("고쳤어요") }
    func toggleStar(_ item: Item) { change { $0.toggleStar(item.id) } }

    func remove(_ item: Item) {
        change { $0.remove(item.id) }
        show("‘\(item.displayTitle)’ 삭제함") { [weak self] in self?.change { $0.restore(item.id) } }
    }

    func copyURL(_ item: Item) {
        UIPasteboard.general.string = item.url
        show("주소를 복사했어요")
    }

    // MARK: 서랍

    func addFolder(name: String, color: FolderColor) { change { $0.addFolder(name: name, color: color) }; show("‘\(name)’ 서랍을 만들었어요") }
    func updateFolder(_ id: String, name: String, color: FolderColor) { change { $0.updateFolder(id, name: name, color: color) } }

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
                    if it.siteName == nil { it.siteName = info?.siteName }
                    if info == nil, it.title.isEmpty, it.note.isEmpty { it.title = guessTitle(url) }
                }
            }
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
        lib.addItem(ItemDraft(kind: .memo, title: "오사카 메모", note: "도톤보리 → 쿠로몬 시장은 아침에", emoji: "✈️", tags: ["여행"]), now: now - 12 * day)
        if let star = lib.liveItems.first(where: { $0.kind == .memo }) { lib.toggleStar(star.id) }
        return lib
    }
}
