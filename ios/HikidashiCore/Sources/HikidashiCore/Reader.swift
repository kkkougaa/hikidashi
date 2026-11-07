import Foundation

/// 리더 모드 한 덩어리
public enum ReaderBlock: Equatable, Sendable {
    case heading(String, level: Int)
    case paragraph(String)
    case quote(String)
    case listItem(String)
    case code(String)
    case image(String)
}

/// 리더 모드로 보여줄 글
public struct ReaderArticle: Equatable, Sendable {
    public var title: String?
    public var siteName: String?
    public var image: String?
    public var blocks: [ReaderBlock]

    public init(title: String? = nil, siteName: String? = nil, image: String? = nil, blocks: [ReaderBlock] = []) {
        self.title = title
        self.siteName = siteName
        self.image = image
        self.blocks = blocks
    }

    /// 본문 글자 수 (너무 짧으면 리더로 보여줄 글이 아니다)
    public var textLength: Int {
        blocks.reduce(0) {
            switch $1 {
            case .paragraph(let t), .quote(let t), .listItem(let t), .code(let t): $0 + t.count
            default: $0
            }
        }
    }

    /// 읽는 데 걸리는 시간(분). 한국어는 분당 약 500자로 친다
    public var minutes: Int { max(1, Int((Double(textLength) / 500).rounded())) }
}

private func regex(_ p: String) -> NSRegularExpression? {
    try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators])
}

private func removing(_ pattern: String, from s: String, with t: String = " ") -> String {
    guard let re = regex(pattern) else { return s }
    return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: t)
}

/// 태그를 걷어내고 글자만. pre 가 아니면 공백을 하나로 모은다
func plainText(_ html: String, keepLines: Bool = false) -> String {
    var s = removing(#"<br\s*/?>"#, from: html, with: "\n")
    s = removing(#"<[^>]+>"#, from: s, with: "")
    s = decodeEntities(s)
    if keepLines {
        return s.trimmingCharacters(in: .newlines)
    }
    s = s.replacingOccurrences(of: #"[ \t\x{00A0}\r]+"#, with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: #" *\n+ *"#, with: "\n", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 링크 글자가 대부분인 덩어리(메뉴, 관련 글 목록)인지
private func linkHeavy(_ inner: String, textLength: Int) -> Bool {
    guard textLength > 0, let re = regex(#"<a\b[^>]*>(.*?)</a\s*>"#) else { return false }
    let ns = inner as NSString
    let linked = re.matches(in: inner, range: NSRange(location: 0, length: ns.length))
        .reduce(0) { $0 + plainText(ns.substring(with: $1.range(at: 1))).count }
    return Double(linked) / Double(textLength) > 0.6
}

private func imageSource(_ tag: String, base: String) -> String? {
    var attrs: [String: String] = [:]
    if let re = try? NSRegularExpression(pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#) {
        let ns = tag as NSString
        for m in re.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let vr = m.range(at: 2).location != NSNotFound ? m.range(at: 2) : m.range(at: 3)
            if vr.location != NSNotFound { attrs[ns.substring(with: m.range(at: 1)).lowercased()] = ns.substring(with: vr) }
        }
    }
    // 늦게 불러오는 그림은 data-src 쪽에 진짜 주소가 있다
    let fromSet = (attrs["data-srcset"] ?? attrs["srcset"]).flatMap { $0.split(separator: ",").last?.split(separator: " ").first.map(String.init) }
    for raw in [attrs["data-src"], attrs["data-original"], attrs["data-lazy-src"], attrs["src"], fromSet] {
        guard let raw else { continue }
        let s = decodeEntities(raw).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !s.hasPrefix("data:"), let u = URL(string: s, relativeTo: URL(string: base)) else { continue }
        let abs = u.absoluteString
        if isContentImage(abs, page: base) { return abs }
    }
    return nil
}

/// 본문이 있을 법한 부분: 가장 글이 많은 <article>, 없으면 <main>, 없으면 <body>
private func mainRegion(_ html: String) -> String {
    func biggest(_ tag: String) -> String? {
        guard let re = regex("<\(tag)\\b[^>]*>(.*?)</\(tag)\\s*>") else { return nil }
        let ns = html as NSString
        let parts = re.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        let scored = parts.map { p in (p, (regex(#"<p\b"#)?.numberOfMatches(in: p, range: NSRange(location: 0, length: (p as NSString).length)) ?? 0)) }
        return scored.max { $0.1 < $1.1 }.flatMap { $0.1 >= 2 ? $0.0 : nil }
    }
    return biggest("article") ?? biggest("main") ?? biggest("body") ?? html
}

/// 페이지 HTML 에서 읽을 본문만 골라낸다 (Readability 를 아주 작게 흉내 낸 것)
public func extractArticle(_ html: String, url: String) -> ReaderArticle {
    let info = parseHTML(html, url: url)
    var s = String(html.prefix(2_000_000))
    for tag in ["script", "style", "noscript", "svg", "template", "iframe", "form", "nav", "footer", "aside", "button", "select", "figcaption"] {
        s = removing("<\(tag)\\b[^>]*>.*?</\(tag)\\s*>", from: s)
    }
    s = removing(#"<!--.*?-->"#, from: s)
    // 글 머리(header)는 제목 줄만 들어 있는 경우가 많아 빼되, 본문 안 h 태그는 남긴다
    s = removing(#"<header\b[^>]*>.*?</header\s*>"#, from: s)
    let region = mainRegion(s)

    guard let re = regex(#"<(h[1-6]|p|li|blockquote|pre)\b[^>]*>(.*?)</\1\s*>|<img\b[^>]*>"#) else { return ReaderArticle(title: info.title, siteName: info.siteName, image: info.image) }
    let ns = region as NSString
    var blocks: [ReaderBlock] = []
    var seenImages = Set<String>()
    if let hero = info.image { seenImages.insert(hero) }
    var seenText = Set<String>()

    func addImages(in fragment: String) {
        guard let ire = regex(#"<img\b[^>]*>"#) else { return }
        let fns = fragment as NSString
        for m in ire.matches(in: fragment, range: NSRange(location: 0, length: fns.length)) {
            if let src = imageSource(fns.substring(with: m.range), base: url), seenImages.insert(src).inserted { blocks.append(.image(src)) }
        }
    }

    for m in re.matches(in: region, range: NSRange(location: 0, length: ns.length)) {
        if m.range(at: 1).location == NSNotFound {
            addImages(in: ns.substring(with: m.range))
            continue
        }
        let tag = ns.substring(with: m.range(at: 1)).lowercased()
        let inner = ns.substring(with: m.range(at: 2))
        let text = plainText(inner, keepLines: tag == "pre")
        if !text.isEmpty, !linkHeavy(inner, textLength: text.count), seenText.insert(text).inserted {
            switch tag {
            case "pre": blocks.append(.code(text))
            case "blockquote": blocks.append(.quote(text))
            case "li": if text.count < 600 { blocks.append(.listItem(text)) }
            case "p": blocks.append(.paragraph(text))
            default:
                let level = Int(tag.dropFirst()) ?? 2
                // 글 제목과 같은 첫 제목 줄은 위에 따로 보여주니 뺀다
                if !(blocks.isEmpty && text == info.title) { blocks.append(.heading(text, level: level)) }
            }
        }
        if tag == "p" || tag == "li" || tag == "blockquote" { addImages(in: inner) }
    }

    // 앞쪽에 글 제목(h1)이 있으면 그걸 제목으로 쓰고, 그 앞의 안내 문구(번역 안내 등)는 뺀다
    var title = info.title
    if let i = blocks.prefix(6).firstIndex(where: { if case .heading(_, 1) = $0 { true } else { false } }),
       case .heading(let h, _) = blocks[i] {
        title = h
        blocks.removeFirst(i + 1)
    }
    // 끝에 남은 제목·짧은 줄(공유하기, 댓글 수 등)은 덜어낸다
    while let last = blocks.last {
        if case .heading = last { blocks.removeLast(); continue }
        if case .paragraph(let t) = last, t.count < 20 { blocks.removeLast(); continue }
        break
    }
    return ReaderArticle(title: title, siteName: info.siteName, image: info.image, blocks: Array(blocks.prefix(600)))
}

/// 네이버 블로그는 본문이 프레임 안에 있어 모바일 주소로 바꿔 읽는다
public func readerURL(_ url: String) -> String {
    guard let u = URL(string: url), let host = u.host?.lowercased() else { return url }
    if host == "blog.naver.com" {
        return "https://m.blog.naver.com" + u.path + (u.query.map { "?" + $0 } ?? "")
    }
    return url
}

/// 리더 모드로 열 만한 링크인지 (X, 유튜브는 원래 화면이 낫다)
public func supportsReader(_ url: String?) -> Bool {
    guard let url, url.hasPrefix("http") else { return false }
    return xStatusID(url) == nil && youtubeID(url) == nil
}

extension PageInfoFetcher {
    /// 리더 모드 본문. 읽을 글이 너무 짧으면 nil
    public func fetchArticle(_ url: String) async -> ReaderArticle? {
        guard let (data, finalURL) = await get(readerURL(url)) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let a = extractArticle(html, url: finalURL)
        return a.textLength >= 200 ? a : nil
    }
}
