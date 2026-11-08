import Foundation

/// www 를 뺀 도메인. 주소가 아니면 빈 문자열
public func domain(of url: String?) -> String {
    guard let url, let host = URLComponents(string: url)?.host?.lowercased() else { return "" }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

/// "example.com/a" 처럼 프로토콜 없이 적어도 https 주소로 바꾼다. 주소가 아니면 nil
public func normalizeURL(_ input: String) -> String? {
    let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty, s.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
    let hasScheme = s.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) != nil
    let withScheme = hasScheme ? s : "https://\(s)"
    guard var c = URLComponents(string: withScheme), let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = c.host, host.contains(".") || host == "localhost" else { return nil }
    c.scheme = scheme
    if c.path.isEmpty { c.path = "/" }
    return c.string.map(cleanURL)
}

/// 어디서나 떼어도 되는 추적용 꼬리
private let trackingParams: Set<String> = [
    "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "li_fat_id",
    "mc_cid", "mc_eid", "igshid", "igsh", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "oly_enc_id", "oly_anon_id",
    "ref_src", "ref_url", "spm", "scm", "__twitter_impression",
]

/// 그 사이트에서만 추적용인 꼬리 (다른 곳에선 뜻이 있을 수 있어 사이트를 가린다)
private let siteTrackingParams: [String: Set<String>] = [
    "youtube.com": ["si", "feature", "pp"],
    "youtu.be": ["si", "feature"],
    "music.youtube.com": ["si", "feature"],
    "open.spotify.com": ["si", "context"],
    "x.com": ["s", "t"],
    "twitter.com": ["s", "t"],
    "instagram.com": ["igsh", "img_index"],
    "threads.net": ["igshid", "xmt", "slof"],
    "threads.com": ["igshid", "xmt", "slof"],
    "linkedin.com": ["trk", "trackingid", "lipi"],
    "coupang.com": ["src", "spec", "addtag", "ctag", "lptag", "itime", "pageType", "pageValue", "wPcid", "wRef", "wTime", "redirect", "isAddedCart", "traceid", "requestid", "sourceType"],
]

/// 주소에서 utm_ 같은 추적 꼬리와 글자 위치 조각(#:~:text=)을 뗀다
public func cleanURL(_ url: String) -> String {
    guard var c = URLComponents(string: url) else { return url }
    let host = domain(of: url)
    let site = siteTrackingParams.first { host == $0.key || host.hasSuffix("." + $0.key) }?.value ?? []
    if let items = c.queryItems {
        let kept = items.filter { q in
            let n = q.name.lowercased()
            return !n.hasPrefix("utm_") && !trackingParams.contains(n) && !site.contains(q.name) && !site.contains(n)
        }
        if kept.count != items.count { c.queryItems = kept.isEmpty ? nil : kept }
    }
    if let f = c.fragment, f.hasPrefix(":~:") { c.fragment = nil }
    return c.string ?? url
}

/// 글 안의 모든 주소 (같은 건 한 번만)
public func findURLs(in text: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: #"https?://[^\s<>"'）)\]]+"#, options: [.caseInsensitive]) else { return [] }
    let ns = text as NSString
    var out: [String] = []
    for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        var raw = ns.substring(with: m.range)
        while let last = raw.last, ".,!?;:".contains(last) { raw.removeLast() }
        if let u = normalizeURL(raw), !out.contains(u) { out.append(u) }
    }
    return out
}

/// 공유로 받은 글 안에서 첫 주소를 찾는다
public func findURL(in text: String) -> String? {
    guard let r = text.range(of: #"https?://[^\s<>"']+"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
    return normalizeURL(String(text[r]))
}

/// 주소에서 제목을 짐작한다: 마지막 경로 조각, 없으면 도메인
public func guessTitle(_ url: String) -> String {
    guard let c = URLComponents(string: url) else { return url }
    if let seg = c.path.split(separator: "/").last {
        var t = String(seg).removingPercentEncoding ?? String(seg)
        t = t.replacingOccurrences(of: #"\.[a-zA-Z0-9]{2,5}$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[-_+]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, t.range(of: #"^\d+$"#, options: .regularExpression) == nil { return t }
    }
    return domain(of: url)
}

/// "참고, #나중에 ,, 참고" → ["참고", "나중에"]
public func parseTags(_ input: String) -> [String] {
    var out: [String] = []
    for raw in input.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isNewline || $0.isWhitespace }) {
        let t = normalizeTag(String(raw))
        if !t.isEmpty, !out.contains(t) { out.append(t) }
    }
    return out
}

public func normalizeTag(_ raw: String) -> String {
    var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while t.hasPrefix("#") { t.removeFirst() }
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - 날짜

public enum Bucket: String, CaseIterable, Sendable {
    case today = "오늘", yesterday = "어제", thisWeek = "이번 주", thisMonth = "이번 달", earlier = "이전"
}

public struct DateText: Sendable {
    public var calendar: Calendar
    public init(calendar: Calendar = .current) {
        var c = calendar
        c.locale = Locale(identifier: "ko_KR")
        self.calendar = c
    }

    public func daysAgo(_ t: Millis, now: Millis = .now) -> Int {
        let a = calendar.startOfDay(for: t.date), b = calendar.startOfDay(for: now.date)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    public func bucket(_ t: Millis, now: Millis = .now) -> Bucket {
        switch daysAgo(t, now: now) {
        case ...0: .today
        case 1: .yesterday
        case 2..<7: .thisWeek
        case 7..<31: .thisMonth
        default: .earlier
        }
    }

    private func format(_ pattern: String, _ t: Millis) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f.string(from: t.date)
    }

    /// 목록 오른쪽 시각: 오늘은 시각, 어제, 이번 주는 요일, 올해는 월일, 그 전은 연월일
    public func stamp(_ t: Millis, now: Millis = .now) -> String {
        let d = daysAgo(t, now: now)
        if d <= 0 { return format("a h:mm", t) }
        if d == 1 { return "어제" }
        if d < 7 { return format("EEEE", t) }
        let sameYear = calendar.component(.year, from: t.date) == calendar.component(.year, from: now.date)
        return sameYear ? format("M월 d일", t) : format("yyyy년 M월 d일", t)
    }

    public func fileStamp(_ t: Millis = .now) -> String { format("yyyyMMdd-HHmm", t) }
}
