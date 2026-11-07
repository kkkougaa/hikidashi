import Foundation

/// 웹앱과 같은 백업 파일 형식 (docs/SPEC.md)
public struct Backup: Codable, Sendable {
    public var app: String = "hikidashi"
    public var version: Int = 1
    public var exportedAt: Millis
    public var folders: [Folder]
    public var items: [Item]

    public init(folders: [Folder], items: [Item], exportedAt: Millis = .now) {
        self.folders = folders
        self.items = items
        self.exportedAt = exportedAt
    }

    public static func fileName(at t: Millis = .now) -> String {
        "hikidashi-backup-\(DateText().fileStamp(t)).json"
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}

public enum BackupError: Error, Equatable, LocalizedError {
    case unreadable, notHikidashi

    public var errorDescription: String? {
        switch self {
        case .unreadable: "백업 파일을 읽을 수 없어요. hikidashi 에서 내보낸 .json 파일인지 확인해주세요."
        case .notHikidashi: "hikidashi 백업 파일이 아니에요."
        }
    }
}

/// 배열 안의 레코드 하나가 깨져도 나머지는 읽기 위한 포장
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private struct RawBackup: Decodable {
    let app: String?
    let version: Int?
    let exportedAt: Double?
    let folders: [Lossy<Folder>]?
    let items: [Lossy<Item>]?
}

/// 가져온 파일을 검사한다. 형식이 틀린 레코드는 빼고 읽는다
public func parseBackup(_ data: Data) throws -> Backup {
    let raw: RawBackup
    do { raw = try JSONDecoder().decode(RawBackup.self, from: data) } catch { throw BackupError.unreadable }
    guard raw.app == "hikidashi", raw.version == 1, let f = raw.folders, let i = raw.items else { throw BackupError.notHikidashi }
    return Backup(folders: f.compactMap(\.value), items: i.compactMap(\.value), exportedAt: Millis(raw.exportedAt ?? 0))
}

public protocol Versioned { var id: String { get }; var updatedAt: Millis { get } }
extension Folder: Versioned {}
extension Item: Versioned {}

/// id 기준으로 합친다. 같은 id 면 더 최근에 고친 쪽이 이긴다. (나중에 서버 동기화도 같은 규칙)
public func mergeRecords<T: Versioned>(_ local: [T], _ incoming: [T]) -> (merged: [T], changed: [T]) {
    var order = local.map(\.id)
    var map = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var changed: [T] = []
    for r in incoming {
        if let cur = map[r.id] {
            if r.updatedAt > cur.updatedAt { map[r.id] = r; changed.append(r) }
        } else {
            map[r.id] = r
            order.append(r.id)
            changed.append(r)
        }
    }
    return (order.compactMap { map[$0] }, changed)
}
