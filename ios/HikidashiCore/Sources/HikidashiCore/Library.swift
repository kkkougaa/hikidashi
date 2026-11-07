import Foundation

/// 서랍과 항목 전체. 화면과 저장 방식에 상관없는 순수 값이라 리눅스에서도 테스트된다.
public struct Library: Codable, Equatable, Sendable {
    public var folders: [Folder]
    public var items: [Item]

    public init(folders: [Folder] = [], items: [Item] = []) {
        self.folders = folders
        self.items = items
    }

    /// 처음 열었을 때 만들어 두는 서랍
    public static func seeded(now: Millis = .now) -> Library {
        Library(folders: [
            Folder(name: "나중에 읽기", color: .blue, order: 0, createdAt: now),
            Folder(name: "참고", color: .cyan, order: 1, createdAt: now),
            Folder(name: "아이디어", color: .orange, order: 2, createdAt: now),
        ])
    }

    // MARK: 읽기

    /// 삭제 표시가 없는 항목, 최신순
    public var liveItems: [Item] { items.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt } }
    /// 삭제 표시가 없는 서랍, 순서대로
    public var liveFolders: [Folder] { folders.filter { $0.deletedAt == nil }.sorted { $0.order < $1.order } }

    public func folder(_ id: String?) -> Folder? {
        guard let id else { return nil }
        return folders.first { $0.id == id && $0.deletedAt == nil }
    }

    public func item(_ id: String) -> Item? { items.first { $0.id == id } }

    /// 태그와 개수, 이름순
    public var tagCounts: [(tag: String, count: Int)] {
        var m: [String: Int] = [:]
        for i in liveItems { for t in i.tags { m[t, default: 0] += 1 } }
        return m.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }.map { ($0.key, $0.value) }
    }

    /// 태그 추천용: 자주 쓴 순
    public var tagsByUse: [String] {
        tagCounts.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }.map(\.tag)
    }

    public func count(inFolder id: String) -> Int { liveItems.filter { $0.folderId == id }.count }

    /// 미분류: 서랍이 없거나 지워진 서랍에 있던 항목
    public var unfiled: [Item] { liveItems.filter { folder($0.folderId) == nil } }

    public func contains(url: String) -> Bool { liveItems.contains { $0.url == url } }

    // MARK: 항목

    @discardableResult
    public mutating func addItem(_ d: ItemDraft, id: String = newID(), now: Millis = .now) -> Item {
        let it = Item(id: id, kind: d.kind, url: d.url, title: d.title, note: d.note, image: d.image, siteName: d.siteName, emoji: d.emoji, folderId: d.folderId, tags: d.tags, createdAt: now)
        items.append(it)
        return it
    }

    public mutating func update(_ id: String, now: Millis = .now, _ change: (inout Item) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        items[i].updatedAt = max(now, items[i].updatedAt + 1)
    }

    public mutating func apply(_ d: ItemDraft, to id: String, now: Millis = .now) {
        update(id, now: now) {
            $0.kind = d.kind; $0.url = d.url; $0.title = d.title; $0.note = d.note
            $0.image = d.image; $0.siteName = d.siteName; $0.emoji = d.emoji; $0.folderId = d.folderId; $0.tags = d.tags
        }
    }

    public mutating func toggleStar(_ id: String, now: Millis = .now) { update(id, now: now) { $0.starred.toggle() } }
    public mutating func remove(_ id: String, now: Millis = .now) { update(id, now: now) { $0.deletedAt = now } }
    public mutating func restore(_ id: String, now: Millis = .now) { update(id, now: now) { $0.deletedAt = nil } }

    // MARK: 서랍

    @discardableResult
    public mutating func addFolder(name: String, color: FolderColor, now: Millis = .now) -> Folder {
        let next = (liveFolders.map(\.order).max() ?? -1) + 1
        let f = Folder(name: name, color: color, order: next, createdAt: now)
        folders.append(f)
        return f
    }

    public mutating func updateFolder(_ id: String, name: String, color: FolderColor, now: Millis = .now) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name
        folders[i].color = color
        folders[i].updatedAt = max(now, folders[i].updatedAt + 1)
    }

    /// 서랍을 지우고 안의 항목은 미분류로 옮긴다. 되돌리기에 쓰도록 옮긴 항목 id 를 돌려준다
    @discardableResult
    public mutating func removeFolder(_ id: String, now: Millis = .now) -> [String] {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return [] }
        folders[i].deletedAt = now
        folders[i].updatedAt = max(now, folders[i].updatedAt + 1)
        let moved = liveItems.filter { $0.folderId == id }.map(\.id)
        for m in moved { update(m, now: now) { $0.folderId = nil } }
        return moved
    }

    public mutating func restoreFolder(_ id: String, moved: [String], now: Millis = .now) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].deletedAt = nil
        folders[i].updatedAt = max(now, folders[i].updatedAt + 1)
        for m in moved where item(m)?.folderId == nil { update(m, now: now) { $0.folderId = id } }
    }

    // MARK: 태그

    /// 태그 이름 바꾸기. 같은 이름이 이미 있으면 합쳐진다. 바뀐 항목 수를 돌려준다
    @discardableResult
    public mutating func renameTag(_ old: String, to new: String, now: Millis = .now) -> Int {
        let to = normalizeTag(new)
        guard !to.isEmpty, to != old else { return 0 }
        let ids = liveItems.filter { $0.tags.contains(old) }.map(\.id)
        for id in ids {
            update(id, now: now) { it in
                var out: [String] = []
                for t in it.tags.map({ $0 == old ? to : $0 }) where !out.contains(t) { out.append(t) }
                it.tags = out
            }
        }
        return ids.count
    }

    /// 모든 항목에서 태그를 뺀다. 바뀐 항목 수를 돌려준다
    @discardableResult
    public mutating func removeTag(_ tag: String, now: Millis = .now) -> Int {
        let ids = liveItems.filter { $0.tags.contains(tag) }.map(\.id)
        for id in ids { update(id, now: now) { $0.tags.removeAll { $0 == tag } } }
        return ids.count
    }

    /// 서랍 순서를 주어진 id 순서로 바꾼다
    public mutating func reorderFolders(_ ids: [String], now: Millis = .now) {
        for (n, id) in ids.enumerated() {
            guard let i = folders.firstIndex(where: { $0.id == id }), folders[i].order != n else { continue }
            folders[i].order = n
            folders[i].updatedAt = max(now, folders[i].updatedAt + 1)
        }
    }

    // MARK: 백업

    public func backup(now: Millis = .now) -> Backup { Backup(folders: folders, items: items, exportedAt: now) }

    /// 더 최근에 고친 것만 들여온다. 바뀐 개수를 돌려준다
    @discardableResult
    public mutating func importBackup(_ b: Backup) -> (items: Int, folders: Int) {
        let f = mergeRecords(folders, b.folders)
        let i = mergeRecords(items, b.items)
        folders = f.merged
        items = i.merged
        return (i.changed.count, f.changed.count)
    }
}
