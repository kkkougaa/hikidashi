import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 링크 점검 결과
public enum LinkHealth: String, Sendable {
    /// 열린다
    case ok
    /// 지워졌거나 주소가 없다 (404, 410, 도메인 없음)
    case broken
    /// 알 수 없다 (막힘, 너무 많은 요청, 서버 오류, 시간 초과) → 표시를 바꾸지 않는다
    case unknown
}

/// 응답 코드나 오류로 판단한다
public func classifyLink(status: Int?, error: URLError.Code? = nil) -> LinkHealth {
    if let error {
        return [.cannotFindHost, .dnsLookupFailed, .unsupportedURL, .badURL].contains(error) ? .broken : .unknown
    }
    guard let status else { return .unknown }
    switch status {
    case 200..<400: return .ok
    case 404, 410: return .broken
    default: return .unknown
    }
}

/// 점검할 차례인지: 처음이거나, 마지막 점검이 days 일보다 오래됐으면
public func needsCheck(_ item: Item, now: Millis = .now, days: Int = 7) -> Bool {
    guard item.kind == .link, item.deletedAt == nil, item.url != nil else { return false }
    guard let last = item.checkedAt else { return true }
    return now - last > Millis(days) * 86_400_000
}

extension PageInfoFetcher {
    /// 링크가 아직 열리는지. X 는 FxTwitter, 유튜브는 oEmbed 로 물어본다 (본 페이지는 늘 200 이라서)
    public func check(_ url: String) async -> LinkHealth {
        var target = url
        if let id = xStatusID(url) {
            target = "https://api.fxtwitter.com/status/\(id)"
        } else if youtubeID(url) != nil {
            let q = url.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url
            target = "https://www.youtube.com/oembed?format=json&url=\(q)"
        }
        guard let u = URL(string: target) else { return .broken }
        for method in ["HEAD", "GET"] {
            var req = URLRequest(url: u, timeoutInterval: timeout)
            req.httpMethod = method
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            if method == "GET" { req.setValue("bytes=0-2048", forHTTPHeaderField: "Range") }
            let r: (Int?, URLError.Code?) = await withCheckedContinuation { cont in
                URLSession.shared.dataTask(with: req) { _, res, err in
                    cont.resume(returning: ((res as? HTTPURLResponse)?.statusCode, (err as? URLError)?.code))
                }.resume()
            }
            let h = classifyLink(status: r.0, error: r.1)
            // HEAD 를 막는 서버(405, 403 등)는 GET 으로 한 번 더
            if method == "HEAD", h == .unknown, r.1 == nil { continue }
            return h
        }
        return .unknown
    }
}
