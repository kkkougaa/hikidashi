import Foundation
import HikidashiCore

/// 오프라인 저장 한 묶음: 받은 때의 항목 모습, 본문, 받은 그림·영상 파일 이름. 동기화하지 않는다 (기기마다)
struct OfflinePack: Codable {
    var savedAt: Millis
    var item: Item
    var article: ReaderArticle?
    /// 원래 주소 → 묶음 폴더 안 파일 이름
    var media: [String: String]
    /// 받지 못한 그림·영상 수
    var failed: Int
}

/// 오프라인 보기로 열 항목
struct OfflineRequest: Identifiable {
    let id: String
}

/// 앱 폴더 offline/<항목 id>/ 에 pack.json 과 받은 파일들. 원본 글이 지워져도, 인터넷이 없어도 본다
enum OfflineDisk {
    static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 영상 하나는 이만큼까지만 받는다 (웹과 같음)
    static let maxBytes: Int64 = 300 * 1024 * 1024

    static func dir(_ id: String) -> URL { folder.appendingPathComponent(id, isDirectory: true) }
    static func file(_ id: String, _ name: String) -> URL { dir(id).appendingPathComponent(name) }

    static var ids: Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { FileManager.default.fileExists(atPath: dir($0).appendingPathComponent("pack.json").path) })
    }

    static func load(_ id: String) -> OfflinePack? {
        (try? Data(contentsOf: dir(id).appendingPathComponent("pack.json"))).flatMap { try? JSONDecoder().decode(OfflinePack.self, from: $0) }
    }

    static func remove(_ id: String) { try? FileManager.default.removeItem(at: dir(id)) }

    /// 이 항목에서 받아 둘 그림·영상 주소 (웹 mediaUrls 와 같은 순서)
    static func mediaURLs(_ item: Item, _ article: ReaderArticle?) -> [String] {
        var list: [String] = [item.video, item.image].compactMap { $0 } + item.images + [item.avatar, article?.image].compactMap { $0 }
        for b in article?.blocks ?? [] { if case .image(let s) = b { list.append(s) } }
        var seen = Set<String>()
        return list.filter { $0.lowercased().hasPrefix("http") && seen.insert($0).inserted }.prefix(40).map { $0 }
    }

    /// 받아서 넣는다. 본문을 못 받아도 항목 모습과 받은 그림·영상은 남긴다
    static func download(_ item: Item, article: ReaderArticle?) async -> OfflinePack? {
        let d = dir(item.id)
        try? FileManager.default.removeItem(at: d)
        guard (try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)) != nil else { return nil }
        var media: [String: String] = [:]
        var failed = 0
        for (n, s) in mediaURLs(item, article).enumerated() {
            guard let url = URL(string: s) else { failed += 1; continue }
            do {
                let (tmp, res) = try await URLSession.shared.download(from: url)
                let http = res as? HTTPURLResponse
                let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
                guard (http?.statusCode ?? 200) < 400, size > 0, size <= maxBytes else { try? FileManager.default.removeItem(at: tmp); failed += 1; continue }
                let ext = url.pathExtension.isEmpty ? (http?.mimeType?.split(separator: "/").last.map(String.init) ?? "bin") : url.pathExtension
                let name = "m\(n).\(ext.prefix(5))"
                try FileManager.default.moveItem(at: tmp, to: file(item.id, name))
                media[s] = name
            } catch {
                failed += 1
            }
        }
        let pack = OfflinePack(savedAt: .now, item: item, article: article, media: media, failed: failed)
        guard let data = try? JSONEncoder().encode(pack) else { return nil }
        try? data.write(to: d.appendingPathComponent("pack.json"), options: .atomic)
        return pack
    }
}
