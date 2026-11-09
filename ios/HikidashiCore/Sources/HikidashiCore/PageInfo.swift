import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 링크에서 가져온 정보. 없는 값은 nil
public struct PageInfo: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var image: String?
    /// 딸린 영상 (X 영상·움짤, 영상 파일 링크)
    public var video: String?
    /// 글 쓴 사람 프로필 사진 (SNS)
    public var avatar: String?
    /// 게시물 사진 전부 (2장 이상일 때만)
    public var images: [String] = []
    public var siteName: String?

    public init(title: String? = nil, description: String? = nil, image: String? = nil, video: String? = nil, siteName: String? = nil) {
        self.title = title
        self.description = description
        self.image = image
        self.video = video
        self.siteName = siteName
    }
}

/// 주소가 영상·움짤·그림 파일 자체면 바로 쓴다 (웹 directMedia 와 같은 규칙)
public func directMedia(_ url: String) -> PageInfo? {
    guard let u = URL(string: url), let host = u.host, !u.lastPathComponent.isEmpty, u.lastPathComponent != "/" else { return nil }
    let name = u.lastPathComponent
    let ext = u.pathExtension.lowercased()
    let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    if ["mp4", "m4v", "webm", "mov"].contains(ext) { return PageInfo(title: name, video: url, siteName: site) }
    if ["gif", "png", "jpg", "jpeg", "webp", "avif"].contains(ext) { return PageInfo(title: name, image: url, siteName: site) }
    return nil
}

/// 사이트 로고 (Google 파비콘 서비스)
public func logoURL(_ url: String?, size: Int = 64) -> String? {
    let host = domain(of: url)
    guard !host.isEmpty else { return nil }
    return "https://www.google.com/s2/favicons?domain=\(host)&sz=\(size)"
}

public func youtubeID(_ url: String) -> String? {
    guard let c = URLComponents(string: url), var host = c.host?.lowercased() else { return nil }
    for p in ["www.", "m."] where host.hasPrefix(p) { host.removeFirst(p.count) }
    if host == "youtu.be" { return c.path.split(separator: "/").first.map(String.init) }
    guard host == "youtube.com" || host == "music.youtube.com" else { return nil }
    if c.path == "/watch" { return c.queryItems?.first { $0.name == "v" }?.value }
    let parts = c.path.split(separator: "/")
    if parts.count >= 2, ["shorts", "embed", "live"].contains(String(parts[0])), parts[1].count >= 6 { return String(parts[1]) }
    return nil
}

/// X(트위터) 게시물 주소면 게시물 id
public func xStatusID(_ url: String) -> String? {
    guard let c = URLComponents(string: url), var host = c.host?.lowercased() else { return nil }
    for p in ["www.", "mobile.", "m."] where host.hasPrefix(p) { host.removeFirst(p.count) }
    guard ["x.com", "twitter.com", "fxtwitter.com", "vxtwitter.com", "fixupx.com", "fixvx.com"].contains(host) else { return nil }
    guard let r = c.path.range(of: #"/status(?:es)?/(\d{5,25})"#, options: .regularExpression) else { return nil }
    return String(c.path[r].split(separator: "/").last ?? "")
}

func clean(_ s: String?) -> String {
    (s ?? "").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// max 자 안쪽으로, 가능하면 단어 경계에서 자른다
public func clip(_ s: String, _ max: Int = 160) -> String {
    guard s.count > max else { return s }
    let cut = String(s.prefix(max))
    var out = cut
    if let sp = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: sp) > Int(Double(max) * 0.6) { out = String(cut[..<sp]) }
    while let last = out.last, " ,.·|:;-".contains(last) { out.removeLast() }
    return out + "…"
}

/// "글 제목 - 사이트" 처럼 붙은 사이트 이름을 뗀다
public func tidyTitle(_ title: String, siteName: String? = nil, host: String? = nil) -> String {
    var t = clean(title)
    let bar = t.components(separatedBy: " | ")
    if bar.count > 1, bar[0].count >= 4 { t = bar[0].trimmingCharacters(in: .whitespaces) }
    let tails = [siteName, siteName?.split(separator: " ").first.map(String.init), host, host?.split(separator: ".").first.map(String.init), "YouTube"].compactMap { $0 }.filter { !$0.isEmpty }
    for tail in tails {
        let escaped = NSRegularExpression.escapedPattern(for: tail)
        let pattern = #"\s*[-|–—:·]\s*"# + escaped + #"\s*$"#
        if let r = t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let rest = String(t[..<r.lowerBound])
            if rest.count >= 2 { t = rest }
        }
    }
    return t
}

// MARK: - HTML

/// 아주 작은 HTML 엔티티 풀기 (메타 태그 값용)
func decodeEntities(_ s: String) -> String {
    var out = s
    let named = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&middot;": "·", "&hellip;": "…"]
    for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
    while let r = out.range(of: #"&#(x[0-9a-fA-F]+|\d+);"#, options: .regularExpression) {
        let body = out[r].dropFirst(2).dropLast()
        let code = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
        out.replaceSubrange(r, with: code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? "")
    }
    return out
}

private func attributes(_ tag: String) -> [String: String] {
    var out: [String: String] = [:]
    guard let re = try? NSRegularExpression(pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#) else { return out }
    let ns = tag as NSString
    for m in re.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
        let key = ns.substring(with: m.range(at: 1)).lowercased()
        let vr = m.range(at: 2).location != NSNotFound ? m.range(at: 2) : m.range(at: 3)
        if vr.location != NSNotFound { out[key] = decodeEntities(ns.substring(with: vr)) }
    }
    return out
}

private func matches(_ pattern: String, in s: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
    let ns = s as NSString
    return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: $0.numberOfRanges > 1 ? 1 : 0)) }
}

private func absolute(_ src: String, base: String) -> String? {
    let s = decodeEntities(src).trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty, !s.hasPrefix("data:") else { return nil }
    guard let u = URL(string: s, relativeTo: URL(string: base)) else { return nil }
    let abs = u.absoluteString
    return abs.hasPrefix("http") ? abs : nil
}

/// 아이콘·로고·광고처럼 글 내용이 아닌 이미지를 거른다
func isContentImage(_ src: String, page: String) -> Bool {
    guard src.hasPrefix("http"), src != page else { return false }
    let l = src.lowercased()
    if l.range(of: #"\.(svg|ico|gif)(\?|$)"#, options: .regularExpression) != nil { return false }
    if l.range(of: #"(favicon|logo|icon|avatar|emoji|sprite|badge|profile|pixel|spacer|tracking|ads?[/_.-])"#, options: .regularExpression) != nil { return false }
    if l.range(of: #"[=_-]s(16|24|32|48|64|88)\b|[?&](w|width|size)=(16|24|32|48|64)\b"#, options: .regularExpression) != nil { return false }
    return true
}

/// 페이지 HTML 에서 제목·소개문·대표 이미지를 뽑는다
public func parseHTML(_ html: String, url: String) -> PageInfo {
    let head = String(html.prefix(400_000))
    var meta: [String: String] = [:]
    for tag in matches(#"(<meta\b[^>]*>)"#, in: head) {
        let a = attributes(tag)
        guard let key = (a["property"] ?? a["name"] ?? a["itemprop"])?.lowercased(), let v = a["content"], !v.isEmpty else { continue }
        if meta[key] == nil { meta[key] = v }
    }
    let host = domain(of: url)
    let siteName = clean(meta["og:site_name"]).nilIfEmpty
    let titleTag = matches(#"<title[^>]*>(.*?)</title>"#, in: head).first.map { decodeEntities($0) }
    let rawTitle = clean(meta["og:title"] ?? meta["twitter:title"] ?? titleTag)

    var desc = clean(meta["og:description"] ?? meta["twitter:description"] ?? meta["description"])
    if desc.isEmpty {
        // 소개문이 없으면 본문 첫 문단
        for p in matches(#"<p\b[^>]*>(.*?)</p>"#, in: head) {
            let text = clean(decodeEntities(p.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)))
            if text.count >= 30 { desc = text; break }
        }
    }

    var image: String?
    if let yt = youtubeID(url) {
        image = "https://i.ytimg.com/vi/\(yt)/hqdefault.jpg"
    } else if let og = meta["og:image"] ?? meta["og:image:url"] ?? meta["twitter:image"] ?? meta["twitter:image:src"], let abs = absolute(og, base: url) {
        image = abs
    } else {
        image = matches(#"<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#, in: head).lazy.compactMap { absolute($0, base: url) }.first { isContentImage($0, page: url) }
    }

    return PageInfo(
        title: rawTitle.isEmpty ? nil : tidyTitle(rawTitle, siteName: siteName, host: host),
        description: desc.isEmpty ? nil : clip(desc),
        image: image,
        siteName: siteName
    )
}

// MARK: - X (트위터)

public struct FxTweet: Decodable, Sendable {
    public struct Author: Decodable, Sendable { public var name: String?; public var screen_name: String?; public var avatar_url: String? }
    public struct Media: Decodable, Sendable {
        public struct Photo: Decodable, Sendable { public var url: String? }
        public struct Video: Decodable, Sendable { public var url: String?; public var thumbnail_url: String?; public var type: String? }
        public var photos: [Photo]?
        public var videos: [Video]?
    }
    public var text: String?
    public var author: Author?
    public var media: Media?
}

/// X 게시물: 제목은 비우고 글 전체를 내용으로. 이미지는 사진 → 영상 썸네일 → 작성자 프로필
public func parseFxTweet(_ t: FxTweet) -> PageInfo {
    let text = (t.text ?? "").replacingOccurrences(of: #"\s*https://t\.co/\w+\s*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    let body = text.isEmpty ? "" : clip(text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression), 400)
    let name = clean(t.author?.name)
    let image = t.media?.photos?.first?.url ?? t.media?.videos?.first?.thumbnail_url ?? t.author?.avatar_url?.replacingOccurrences(of: "_normal.", with: "_200x200.")
    var info = PageInfo(
        title: body.isEmpty && !name.isEmpty ? "\(name)의 게시물" : nil,
        description: body.nilIfEmpty,
        image: image,
        // 영상·움짤(X 는 움짤도 mp4)
        video: t.media?.videos?.first(where: { $0.url != nil })?.url,
        siteName: t.author?.screen_name.map { "X · @\($0)" } ?? "X"
    )
    info.avatar = t.author?.avatar_url?.replacingOccurrences(of: "_normal.", with: "_200x200.")
    let photos = (t.media?.photos ?? []).compactMap(\.url)
    if photos.count > 1 { info.images = Array(photos.prefix(4)) }
    return info
}

// MARK: - 가져오기

/// 앱은 CORS 가 없어 페이지를 직접 읽는다. X 만 FxTwitter, 유튜브는 oEmbed 로 제목을 보탠다
public struct PageInfoFetcher: Sendable {
    public var timeout: TimeInterval = 12
    public init(timeout: TimeInterval = 12) { self.timeout = timeout }

    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    func get(_ url: String) async -> (Data, String)? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("ko-KR,ko;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        return await withCheckedContinuation { cont in
            URLSession.shared.dataTask(with: req) { data, res, _ in
                guard let data, let http = res as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return cont.resume(returning: nil) }
                cont.resume(returning: (data, http.url?.absoluteString ?? url))
            }.resume()
        }
    }

    public func fetch(_ url: String) async -> PageInfo? {
        if let direct = directMedia(url) { return direct }
        if let id = xStatusID(url), let (data, _) = await get("https://api.fxtwitter.com/status/\(id)"),
           let body = try? JSONDecoder().decode(FxBody.self, from: data), let tweet = body.tweet {
            return parseFxTweet(tweet)
        }
        if let yt = youtubeID(url) {
            let q = url.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url
            if let (data, _) = await get("https://www.youtube.com/oembed?format=json&url=\(q)"),
               let o = try? JSONDecoder().decode(OEmbed.self, from: data) {
                return PageInfo(title: o.title.map { tidyTitle($0) }, description: nil, image: "https://i.ytimg.com/vi/\(yt)/hqdefault.jpg", siteName: "YouTube")
            }
        }
        guard let (data, finalURL) = await get(url) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let info = parseHTML(html, url: finalURL)
        return info.title == nil && info.description == nil && info.image == nil ? nil : info
    }

    private struct FxBody: Decodable { var tweet: FxTweet? }
    private struct OEmbed: Decodable { var title: String? }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
