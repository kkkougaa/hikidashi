import Foundation
import Security
import HikidashiCore

/// 앱 저장소 (앱 폴더의 library.json, 백업과 같은 형식)
enum SharedLibrary {
    /// 새 항목과 공유로 들어온 항목이 들어갈 서랍 ("" 이면 첫 번째 서랍, "none" 이면 미분류)
    static let defaultFolderKey = "defaultFolderId"

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    static func load(_ url: URL = fileURL) -> Library? {
        guard let data = try? Data(contentsOf: url), let b = try? parseBackup(data) else { return nil }
        return Library(folders: b.folders, items: b.items)
    }

    static func save(_ lib: Library, to url: URL = fileURL) throws {
        try lib.backup().encoded().write(to: url, options: .atomic)
    }

    /// 설정에 맞는 기본 서랍
    static func defaultFolderId(in lib: Library) -> String? {
        let v = UserDefaults.standard.string(forKey: defaultFolderKey) ?? ""
        if v == "none" { return nil }
        if let f = lib.folder(v) { return f.id }
        return lib.liveFolders.first?.id
    }
}

/// 공유 확장 → 앱 우편함. 같은 팀 앱끼리 쓸 수 있는 키체인 그룹에 담아 둔다
/// (App Group 은 개발자 사이트에서 따로 만들어야 해서, 기본으로 허용되는 키체인 공유를 쓴다)
enum ShareInbox {
    struct Entry: Codable {
        var draft: ItemDraftData
        var sharedAt: Millis
    }

    /// ItemDraft 를 그대로 담는 저장용 모양
    struct ItemDraftData: Codable {
        var kind: String
        var url: String?
        var title: String
        var note: String
        var image: String?
        var siteName: String?

        init(_ d: ItemDraft) {
            kind = d.kind.rawValue; url = d.url; title = d.title; note = d.note; image = d.image; siteName = d.siteName
        }

        func draft(folderId: String?) -> ItemDraft {
            ItemDraft(kind: ItemKind(rawValue: kind) ?? .link, url: url, title: title, note: note, image: image, siteName: siteName, folderId: folderId)
        }
    }

    private static let service = "com.kkkougaa.hikidashi.inbox"

    /// "팀ID.com.kkkougaa.hikidashi.shared" (팀 ID 는 빌드할 때 Info.plist 에 들어간다)
    private static var accessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String, !prefix.isEmpty else { return nil }
        return prefix + "com.kkkougaa.hikidashi.shared"
    }

    private static func base() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let g = accessGroup { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    @discardableResult
    static func put(_ d: ItemDraft) -> Bool {
        guard let data = try? JSONEncoder().encode(Entry(draft: ItemDraftData(d), sharedAt: .now)) else { return false }
        var q = base()
        q[kSecAttrAccount as String] = UUID().uuidString
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    /// 쌓인 것을 꺼내고 비운다 (오래된 것부터)
    static func drain() -> [Entry] {
        var q = base()
        q[kSecReturnAttributes as String] = true
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let rows = out as? [[String: Any]] else { return [] }
        let entries = rows.compactMap { ($0[kSecValueData as String] as? Data).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) } }
        SecItemDelete(base() as CFDictionary)
        return entries.sorted { $0.sharedAt < $1.sharedAt }
    }
}
