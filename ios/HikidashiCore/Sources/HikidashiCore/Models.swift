import Foundation

/// 밀리초 단위 유닉스 시간 (웹의 `Date.now()` 와 같은 값)
public typealias Millis = Int64

public extension Millis {
    static var now: Millis { Millis((Date().timeIntervalSince1970 * 1000).rounded()) }
    var date: Date { Date(timeIntervalSince1970: Double(self) / 1000) }
}

public func newID() -> String { UUID().uuidString.lowercased() }

/// 서랍 색. 흰 글자가 4.5:1 이상 나오는 진한 색만 쓴다. 웹 `src/data/types.ts` 의 COLORS 와 같아야 한다.
public enum FolderColor: String, CaseIterable, Codable, Sendable {
    case red, orange, brown, mustard, lime, green, forest, teal, cyan, sky, blue, navy, purple, plum, magenta, gray, charcoal

    public var hex: String {
        switch self {
        case .red: "#D02B2B"
        case .orange: "#B95300"
        case .brown: "#8B5A2B"
        case .mustard: "#8A6A00"
        case .lime: "#4D7C0F"
        case .green: "#16804A"
        case .forest: "#166534"
        case .teal: "#0F766E"
        case .cyan: "#007F96"
        case .sky: "#0369A1"
        case .blue: "#1366E0"
        case .navy: "#1E3A8A"
        case .purple: "#6B3FD6"
        case .plum: "#86198F"
        case .magenta: "#C2185B"
        case .gray: "#5F646C"
        case .charcoal: "#2F343B"
        }
    }

    public var koreanName: String {
        switch self {
        case .red: "빨강"
        case .orange: "주황"
        case .brown: "갈색"
        case .mustard: "겨자"
        case .lime: "연두"
        case .green: "초록"
        case .forest: "숲초록"
        case .teal: "청록"
        case .cyan: "하늘청록"
        case .sky: "하늘"
        case .blue: "파랑"
        case .navy: "남색"
        case .purple: "보라"
        case .plum: "자두"
        case .magenta: "자홍"
        case .gray: "회색"
        case .charcoal: "먹색"
        }
    }

    /// 0...1 범위 RGB
    public var rgb: (r: Double, g: Double, b: Double) {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

public struct Folder: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var color: FolderColor
    public var order: Int
    public var createdAt: Millis
    public var updatedAt: Millis
    public var deletedAt: Millis?

    public init(id: String = newID(), name: String, color: FolderColor, order: Int, createdAt: Millis = .now, updatedAt: Millis? = nil, deletedAt: Millis? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey { case id, name, color, order, createdAt, updatedAt, deletedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decode(FolderColor.self, forKey: .color)
        order = Int(try c.decodeNumber(forKey: .order))
        createdAt = try c.decodeNumber(forKey: .createdAt)
        updatedAt = try c.decodeNumber(forKey: .updatedAt)
        deletedAt = try c.decodeNumberIfPresent(forKey: .deletedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(color, forKey: .color)
        try c.encode(order, forKey: .order)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        // 웹은 deletedAt 이 null 이어야 읽으므로 비어 있어도 null 로 쓴다
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

public enum ItemKind: String, Codable, Sendable { case link, memo }

public struct Item: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ItemKind
    public var url: String?
    public var title: String
    /// 링크는 내용(페이지 소개문), 메모는 본문
    public var note: String
    public var image: String?
    public var siteName: String?
    public var emoji: String?
    public var folderId: String?
    public var tags: [String]
    public var starred: Bool
    public var createdAt: Millis
    public var updatedAt: Millis
    public var deletedAt: Millis?
    /// 리더에서 형광펜 친 문단들
    public var highlights: [String] = []
    /// 링크가 열리지 않는 걸 처음 알게 된 때 (열리면 nil)
    public var brokenAt: Millis?
    /// 링크 점검을 마지막으로 한 때
    public var checkedAt: Millis?

    public init(id: String = newID(), kind: ItemKind, url: String? = nil, title: String = "", note: String = "", image: String? = nil, siteName: String? = nil, emoji: String? = nil, folderId: String? = nil, tags: [String] = [], starred: Bool = false, createdAt: Millis = .now, updatedAt: Millis? = nil, deletedAt: Millis? = nil) {
        self.id = id
        self.kind = kind
        self.url = url
        self.title = title
        self.note = note
        self.image = image
        self.siteName = siteName
        self.emoji = emoji
        self.folderId = folderId
        self.tags = tags
        self.starred = starred
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey { case id, kind, url, title, note, image, siteName, emoji, folderId, tags, starred, createdAt, updatedAt, deletedAt, highlights, brokenAt, checkedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ItemKind.self, forKey: .kind)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        note = try c.decode(String.self, forKey: .note)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        siteName = try c.decodeIfPresent(String.self, forKey: .siteName)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        tags = try c.decode([String].self, forKey: .tags)
        starred = try c.decode(Bool.self, forKey: .starred)
        createdAt = try c.decodeNumber(forKey: .createdAt)
        updatedAt = try c.decodeNumber(forKey: .updatedAt)
        deletedAt = try c.decodeNumberIfPresent(forKey: .deletedAt)
        highlights = (try? c.decodeIfPresent([String].self, forKey: .highlights)) ?? []
        brokenAt = try? c.decodeNumberIfPresent(forKey: .brokenAt)
        checkedAt = try? c.decodeNumberIfPresent(forKey: .checkedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encode(title, forKey: .title)
        try c.encode(note, forKey: .note)
        try c.encodeIfPresent(image, forKey: .image)
        try c.encodeIfPresent(siteName, forKey: .siteName)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encode(folderId, forKey: .folderId) // 미분류는 null
        try c.encode(tags, forKey: .tags)
        try c.encode(starred, forKey: .starred)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
        if !highlights.isEmpty { try c.encode(highlights, forKey: .highlights) }
        try c.encodeIfPresent(brokenAt, forKey: .brokenAt)
        try c.encodeIfPresent(checkedAt, forKey: .checkedAt)
    }

    /// 목록 제목: 제목이 없으면 내용 첫 줄, 그것도 없으면 도메인
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if let first = note.lines.first { return first }
        return kind == .memo ? "제목 없는 메모" : domain(of: url)
    }

    /// 제목 아래 줄: 제목이 내용 첫 줄을 빌려 썼으면 그다음 줄부터
    public var displaySubtitle: String {
        (title.isEmpty ? Array(note.lines.dropFirst()) : note.lines).joined(separator: " ")
    }
}

/// 추가·편집 폼이 넘기는 값
public struct ItemDraft: Equatable, Sendable {
    public var kind: ItemKind
    public var url: String?
    public var title: String
    public var note: String
    public var image: String?
    public var siteName: String?
    public var emoji: String?
    public var folderId: String?
    public var tags: [String]

    public init(kind: ItemKind, url: String? = nil, title: String = "", note: String = "", image: String? = nil, siteName: String? = nil, emoji: String? = nil, folderId: String? = nil, tags: [String] = []) {
        self.kind = kind
        self.url = url
        self.title = title
        self.note = note
        self.image = image
        self.siteName = siteName
        self.emoji = emoji
        self.folderId = folderId
        self.tags = tags
    }
}

extension String {
    /// 빈 줄을 뺀, 앞뒤 공백을 지운 줄들
    var lines: [String] {
        split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// JSON 숫자가 정수든 실수든 받는다 (JS 숫자는 구분이 없다)
extension KeyedDecodingContainer {
    func decodeNumber(forKey key: Key) throws -> Millis {
        if let i = try? decode(Int64.self, forKey: key) { return i }
        let d = try decode(Double.self, forKey: key)
        guard d.isFinite else { throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not finite") }
        return Millis(d.rounded())
    }

    func decodeNumberIfPresent(forKey key: Key) throws -> Millis? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeNumber(forKey: key)
    }
}
