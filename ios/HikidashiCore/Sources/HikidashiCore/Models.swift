import Foundation

/// 밀리초 단위 유닉스 시간 (웹의 `Date.now()` 와 같은 값)
public typealias Millis = Int64

public extension Millis {
    static var now: Millis { Millis((Date().timeIntervalSince1970 * 1000).rounded()) }
    var date: Date { Date(timeIntervalSince1970: Double(self) / 1000) }
}

public func newID() -> String { UUID().uuidString.lowercased() }

/// 서랍 색. 흰 굵은 글자가 3:1 이상 나오는 밝은 색만 쓴다. 웹 `src/data/types.ts` 의 COLORS 와 같아야 한다.
public enum FolderColor: String, CaseIterable, Codable, Sendable {
    case red, orange, brown, mustard, lime, green, forest, teal, cyan, sky, blue, navy, purple, plum, magenta, gray, charcoal

    public var hex: String {
        switch self {
        case .red: "#F04D4D"
        case .orange: "#E8690A"
        case .brown: "#BA7A3E"
        case .mustard: "#B38400"
        case .lime: "#5C9A16"
        case .green: "#1E9E55"
        case .forest: "#2F9459"
        case .teal: "#14988F"
        case .cyan: "#0B97B8"
        case .sky: "#2B8FD9"
        case .blue: "#3D7FF5"
        case .navy: "#5B6AE6"
        case .purple: "#9168F7"
        case .plum: "#B654CA"
        case .magenta: "#E3478A"
        case .gray: "#7F858F"
        case .charcoal: "#565D68"
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
    public var rgb: (r: Double, g: Double, b: Double) { hexRGB(hex) }

    /// 팔레트로 직접 고른 색에 가장 가까운 기본 색 (옛 앱은 이 색으로 보인다). 웹 nearestColor 와 같은 계산
    public static func nearest(toHex h: String) -> FolderColor {
        let (r, g, b) = hexRGB(h)
        return allCases.min { a, c in
            func d(_ x: FolderColor) -> Double {
                let (p, q, s) = x.rgb
                return pow((r - p) * 255, 2) * 2 + pow((g - q) * 255, 2) * 4 + pow((b - s) * 255, 2) * 3
            }
            return d(a) < d(c)
        } ?? .blue
    }
}

/// "#RRGGBB" 인지
public func isHexColor(_ s: String?) -> Bool {
    guard let s, s.count == 7, s.first == "#" else { return false }
    return s.dropFirst().allSatisfy(\.isHexDigit)
}

/// "#RRGGBB" → 0...1 RGB
public func hexRGB(_ hex: String) -> (r: Double, g: Double, b: Double) {
    let v = Int(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
    return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}

/// 이 색 위에 흰 글자를 올려도 되는지 (대비 2.6:1 이상). 아니면 검정 글자를 쓴다
public func whiteReadsOn(_ hex: String) -> Bool {
    let (r, g, b) = hexRGB(hex)
    func ch(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    let l = 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
    return 1.05 / (l + 0.05) >= 2.6
}

public struct Folder: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var color: FolderColor
    public var order: Int
    public var createdAt: Millis
    public var updatedAt: Millis
    public var deletedAt: Millis?
    /// 하위 서랍이면 상위 서랍 id (한 단계만). 하위 서랍은 화면에서 상위 서랍 색을 따른다
    public var parentId: String?
    /// 팔레트로 직접 고른 색 "#RRGGBB". 있으면 color 대신 쓴다 (color 는 가장 가까운 기본 색)
    public var hex: String?

    /// 화면에 칠할 색 "#RRGGBB"
    public var paintHex: String { isHexColor(hex) ? hex! : color.hex }

    public init(id: String = newID(), name: String, color: FolderColor, order: Int, createdAt: Millis = .now, updatedAt: Millis? = nil, deletedAt: Millis? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey { case id, name, color, order, createdAt, updatedAt, deletedAt, parentId, hex }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decode(FolderColor.self, forKey: .color)
        order = Int(try c.decodeNumber(forKey: .order))
        createdAt = try c.decodeNumber(forKey: .createdAt)
        updatedAt = try c.decodeNumber(forKey: .updatedAt)
        deletedAt = try c.decodeNumberIfPresent(forKey: .deletedAt)
        parentId = try? c.decodeIfPresent(String.self, forKey: .parentId)
        hex = (try? c.decodeIfPresent(String.self, forKey: .hex)).flatMap { isHexColor($0) ? $0 : nil }
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
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encodeIfPresent(hex, forKey: .hex)
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
    /// 링크에 딸린 영상 주소 (mp4 등). 카드에서 2초만 소리 없이 반복 재생한다
    public var video: String?
    /// 확인 완료한 때. 있으면 목록에서 빠지고 "완료함" 에만 보인다
    public var doneAt: Millis?
    /// 글 쓴 사람 프로필 사진 (X 등 SNS). 타임라인 보기의 동그란 사진 자리
    public var avatar: String?
    /// 게시물에 붙은 사진 전부 (X 는 최대 4장). 비면 저장하지 않는다
    public var images: [String] = []
    public var siteName: String?
    public var emoji: String?
    /// 사진에서 잘라 만든 아이콘 (작은 data URL). emoji 다음으로, 글 이미지·로고보다 먼저 쓴다
    public var icon: String?
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

    enum CodingKeys: String, CodingKey { case id, kind, url, title, note, image, video, doneAt, avatar, images, siteName, emoji, icon, folderId, tags, starred, createdAt, updatedAt, deletedAt, highlights, brokenAt, checkedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ItemKind.self, forKey: .kind)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        note = try c.decode(String.self, forKey: .note)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        video = try c.decodeIfPresent(String.self, forKey: .video)
        doneAt = try? c.decodeNumberIfPresent(forKey: .doneAt)
        avatar = try? c.decodeIfPresent(String.self, forKey: .avatar)
        images = (try? c.decodeIfPresent([String].self, forKey: .images)) ?? []
        siteName = try c.decodeIfPresent(String.self, forKey: .siteName)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        icon = try? c.decodeIfPresent(String.self, forKey: .icon)
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
        try c.encodeIfPresent(video, forKey: .video)
        try c.encodeIfPresent(doneAt, forKey: .doneAt)
        try c.encodeIfPresent(avatar, forKey: .avatar)
        if !images.isEmpty { try c.encode(images, forKey: .images) }
        try c.encodeIfPresent(siteName, forKey: .siteName)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encodeIfPresent(icon, forKey: .icon)
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
        if let first = RichText.plain(note).lines.first { return first }
        return kind == .memo ? "제목 없는 메모" : domain(of: url)
    }

    /// 제목 아래 줄: 제목이 내용 첫 줄을 빌려 썼으면 그다음 줄부터
    public var displaySubtitle: String {
        let ls = RichText.plain(note).lines
        return (title.isEmpty ? Array(ls.dropFirst()) : ls).joined(separator: " ")
    }
}

/// 추가·편집 폼이 넘기는 값
public struct ItemDraft: Equatable, Sendable {
    public var kind: ItemKind
    public var url: String?
    public var title: String
    public var note: String
    public var image: String?
    public var video: String?
    public var avatar: String?
    public var images: [String] = []
    public var siteName: String?
    public var emoji: String?
    public var icon: String?
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
