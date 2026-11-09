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

    // MARK: NSFW (태그로 단다, 대소문자 상관없이)

    public static let nsfwTag = "nsfw"
    public static func isNsfw(_ i: Item) -> Bool { i.tags.contains { $0.lowercased() == nsfwTag } }
    public static func withNsfw(_ tags: [String], _ on: Bool) -> [String] {
        if on { return tags.contains { $0.lowercased() == nsfwTag } ? tags : tags + [nsfwTag] }
        return tags.filter { $0.lowercased() != nsfwTag }
    }

    /// 미분류: 서랍이 없거나 지워진 서랍에 있던 항목
    public var unfiled: [Item] { liveItems.filter { folder($0.folderId) == nil } }

    public func contains(url: String) -> Bool { liveItems.contains { $0.url == url } }

    // MARK: 항목

    @discardableResult
    public mutating func addItem(_ d: ItemDraft, id: String = newID(), now: Millis = .now) -> Item {
        var it = Item(id: id, kind: d.kind, url: d.url, title: d.title, note: d.note, image: d.image, siteName: d.siteName, emoji: d.emoji, folderId: d.folderId, tags: d.tags, createdAt: now)
        it.video = d.video
        it.avatar = d.avatar
        it.images = d.images
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
            $0.image = d.image; $0.video = d.video; $0.avatar = d.avatar; $0.images = d.images; $0.siteName = d.siteName; $0.emoji = d.emoji; $0.folderId = d.folderId; $0.tags = d.tags
        }
    }

    public mutating func toggleStar(_ id: String, now: Millis = .now) { update(id, now: now) { $0.starred.toggle() } }

    /// 문단에 형광펜 치기·지우기
    public mutating func toggleHighlight(_ id: String, text: String, now: Millis = .now) {
        update(id, now: now) { it in
            if let i = it.highlights.firstIndex(of: text) { it.highlights.remove(at: i) } else { it.highlights.append(text) }
        }
    }

    /// 링크 점검 결과를 적는다. 깨짐 여부가 바뀔 때만 수정 시각을 올린다 (동기화가 괜히 늘지 않게)
    public mutating func recordCheck(_ id: String, _ health: LinkHealth, now: Millis = .now) {
        guard let i = items.firstIndex(where: { $0.id == id }), health != .unknown else { return }
        let wasBroken = items[i].brokenAt != nil
        let isBroken = health == .broken
        items[i].checkedAt = now
        if wasBroken != isBroken {
            items[i].brokenAt = isBroken ? now : nil
            items[i].updatedAt = max(now, items[i].updatedAt + 1)
        }
    }

    /// 형광펜이 있는 항목, 최근 고친 순
    public var highlighted: [Item] { liveItems.filter { !$0.highlights.isEmpty }.sorted { $0.updatedAt > $1.updatedAt } }
    /// 열리지 않는 링크
    public var broken: [Item] { liveItems.filter { $0.brokenAt != nil } }
    public mutating func remove(_ id: String, now: Millis = .now) { update(id, now: now) { $0.deletedAt = now } }
    public mutating func restore(_ id: String, now: Millis = .now) { update(id, now: now) { $0.deletedAt = nil } }

    // MARK: 서랍

    /// parentId 를 주면 그 서랍의 하위 서랍 (색은 상위 서랍 것)
    @discardableResult
    public mutating func addFolder(name: String, color: FolderColor, parentId: String? = nil, now: Millis = .now) -> Folder {
        let parent = folder(parentId).flatMap { isChild($0) ? nil : $0 }
        let siblings = liveFolders.filter { f in (isChild(f) ? f.parentId : nil) == parent?.id }
        let next = (siblings.map(\.order).max() ?? -1) + 1
        var f = Folder(name: name, color: parent?.color ?? color, order: next, createdAt: now)
        f.parentId = parent?.id
        folders.append(f)
        return f
    }

    /// parentId: nil 이면 그대로, .some(nil) 이면 맨 위로, .some(id) 면 그 서랍 아래로
    public mutating func updateFolder(_ id: String, name: String, color: FolderColor, parentId: String?? = nil, now: Millis = .now) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name
        folders[i].color = color
        if let p = parentId {
            let parent = folder(p).flatMap { $0.id != id && !isChild($0) ? $0 : nil }
            folders[i].parentId = parent?.id
            if let parent { folders[i].color = parent.color }
        }
        folders[i].updatedAt = max(now, folders[i].updatedAt + 1)
    }

    /// 서랍(과 하위 서랍)을 지우고 안의 항목은 미분류로 옮긴다. 되돌리기에 쓰도록 옮긴 항목 id 를 돌려준다
    @discardableResult
    public mutating func removeFolder(_ id: String, now: Millis = .now) -> [String] {
        guard folders.contains(where: { $0.id == id }) else { return [] }
        let gone = [id] + liveFolders.filter { $0.parentId == id && $0.id != id }.map(\.id)
        var moved: [String] = []
        for fid in gone {
            guard let i = folders.firstIndex(where: { $0.id == fid }) else { continue }
            folders[i].deletedAt = now
            folders[i].updatedAt = max(now, folders[i].updatedAt + 1)
            let these = liveItems.filter { $0.folderId == fid }.map(\.id)
            for m in these { update(m, now: now) { $0.folderId = nil } }
            // 되돌릴 때 어느 서랍이었는지 알도록 "항목id|서랍id"
            moved += these.map { "\($0)|\(fid)" }
        }
        return moved
    }

    public mutating func restoreFolder(_ id: String, moved: [String], now: Millis = .now) {
        let pairs = moved.map { m -> (item: String, folder: String) in
            let p = m.split(separator: "|", maxSplits: 1).map(String.init)
            return p.count == 2 ? (item: p[0], folder: p[1]) : (item: m, folder: id)
        }
        for fid in Set([id] + pairs.map(\.folder)) {
            guard let i = folders.firstIndex(where: { $0.id == fid }) else { continue }
            folders[i].deletedAt = nil
            folders[i].updatedAt = max(now, folders[i].updatedAt + 1)
        }
        for p in pairs where item(p.item)?.folderId == nil { update(p.item, now: now) { $0.folderId = p.folder } }
    }

    // MARK: 하위 서랍 (한 단계)

    /// 하위 서랍인지 (상위 서랍이 살아 있을 때만)
    public func isChild(_ f: Folder) -> Bool {
        guard let p = f.parentId, p != f.id else { return false }
        return folder(p) != nil
    }

    /// 화면에 보이는 이름: 하위 서랍은 "상위-하위"
    public func displayName(_ f: Folder) -> String {
        guard isChild(f), let p = folder(f.parentId) else { return f.name }
        return "\(p.name)-\(f.name)"
    }

    /// 화면에 보이는 색: 하위 서랍은 상위 서랍 색
    public func displayColor(_ f: Folder) -> FolderColor {
        guard isChild(f), let p = folder(f.parentId) else { return f.color }
        return p.color
    }

    /// 위 단계 서랍 순서대로, 각 서랍 바로 뒤에 하위 서랍
    public var orderedFolders: [(folder: Folder, depth: Int)] {
        let live = liveFolders
        var out: [(folder: Folder, depth: Int)] = []
        for top in live where !isChild(top) {
            out.append((folder: top, depth: 0))
            for c in live where c.parentId == top.id && isChild(c) { out.append((folder: c, depth: 1)) }
        }
        return out
    }

    /// 서랍과 그 하위 서랍 id
    public func family(_ id: String) -> Set<String> {
        Set([id] + liveFolders.filter { $0.parentId == id && $0.id != id }.map(\.id))
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
