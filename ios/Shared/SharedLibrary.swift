import Foundation
import HikidashiCore

/// 앱과 공유 확장이 함께 쓰는 저장소 (App Group 폴더의 library.json)
enum SharedLibrary {
    static let appGroup = "group.com.kkkougaa.hikidashi"

    /// 앱과 공유 확장이 같이 읽는 설정
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// 새 항목과 공유로 들어온 항목이 들어갈 서랍 ("" 이면 첫 번째 서랍, "none" 이면 미분류)
    static let defaultFolderKey = "defaultFolderId"

    /// App Group 을 못 쓰면(서명 없는 테스트 빌드 등) 앱 폴더를 쓴다
    static var fileURL: URL {
        let fm = FileManager.default
        let old = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("library.json")
        guard let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            try? fm.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
            return old
        }
        let url = group.appendingPathComponent("library.json")
        // 예전 버전이 앱 폴더에 저장했으면 한 번 옮긴다
        if !fm.fileExists(atPath: url.path), fm.fileExists(atPath: old.path) { try? fm.copyItem(at: old, to: url) }
        return url
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
        let v = defaults.string(forKey: defaultFolderKey) ?? ""
        if v == "none" { return nil }
        if let f = lib.folder(v) { return f.id }
        return lib.liveFolders.first?.id
    }
}
