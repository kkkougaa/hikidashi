import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import HikidashiCore

/// 드롭박스 연결 (웹 src/data/dropbox.ts 와 같은 흐름, OAuth PKCE).
/// "App folder" 권한이라 드롭박스의 /앱/hikidashi 폴더만 보고, 그 안에 잠근 파일 하나만 둔다.
/// 갱신 토큰은 키체인(이 기기에만)에 두어 연결을 끊기 전까지 다시 로그인하지 않는다.
@MainActor
final class Dropbox {
    static let shared = Dropbox()
    static let path = "/hikidashi-sync.enc"

    /// 빌드할 때 DROPBOX_APP_KEY 로 넣는다 (Info.plist DropboxAppKey). 비밀값이 아니다
    let appKey: String = {
        let k = (Bundle.main.object(forInfoDictionaryKey: "DropboxAppKey") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return k.hasPrefix("$(") ? "" : k
    }()
    var configured: Bool { !appKey.isEmpty }
    var isConnected: Bool { SyncKeychain.read(.dropboxRefresh) != nil }
    private var redirect: String { "db-\(appKey)://2/token" }

    enum Failure: LocalizedError {
        case notConnected, cancelled, denied, server(String)
        var errorDescription: String? {
            switch self {
            case .notConnected: "드롭박스 연결이 끊겼어요. 다시 연결해주세요"
            case .cancelled: "취소했어요"
            case .denied: "드롭박스에 연결하지 못했어요"
            case .server(let s): "드롭박스 오류 (\(s))"
            }
        }
    }

    private var access: (token: String, until: Date)?
    private var session: ASWebAuthenticationSession?
    private var anchor: AnchorProvider?

    // MARK: 로그인

    func login() async throws {
        let verifier = Self.randomText(48)
        let challenge = Self.b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomText(16)
        var c = URLComponents(string: "https://www.dropbox.com/oauth2/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: appKey),
            .init(name: "response_type", value: "code"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "token_access_type", value: "offline"),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "state", value: state),
        ]
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let provider = AnchorProvider(window: window ?? UIWindow())
        anchor = provider
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "db-\(appKey)") { url, error in
                if let url { cont.resume(returning: url) } else {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    cont.resume(throwing: cancelled ? Failure.cancelled : Failure.denied)
                }
            }
            s.presentationContextProvider = provider
            session = s
            if !s.start() { cont.resume(throwing: Failure.denied) }
        }
        session = nil
        let q = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard q.first(where: { $0.name == "state" })?.value == state, let code = q.first(where: { $0.name == "code" })?.value else { throw Failure.denied }
        let j = try await tokenRequest(["grant_type": "authorization_code", "code": code, "client_id": appKey, "code_verifier": verifier, "redirect_uri": redirect])
        guard let refresh = j["refresh_token"] as? String, let token = j["access_token"] as? String else { throw Failure.denied }
        SyncKeychain.write(.dropboxRefresh, Data(refresh.utf8))
        access = (token, Date().addingTimeInterval(Double(j["expires_in"] as? Int ?? 3600) - 60))
    }

    /// 이 기기에서 끊는다 (드롭박스 쪽 토큰도 취소)
    func disconnect() async {
        if isConnected {
            var req = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/auth/token/revoke")!)
            req.httpMethod = "POST"
            _ = try? await call(req)
        }
        access = nil
        SyncKeychain.delete(.dropboxRefresh)
    }

    // MARK: 파일

    func rev() async throws -> String? {
        let (data, res) = try await rpc("files/get_metadata", ["path": Self.path])
        if res.statusCode == 409, Self.summary(data).hasPrefix("path/not_found") { return nil }
        try Self.check(data, res)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["rev"] as? String
    }

    func read() async throws -> (data: Data, rev: String)? {
        var req = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        req.httpMethod = "POST"
        req.setValue(Self.json(["path": Self.path]), forHTTPHeaderField: "Dropbox-API-Arg")
        let (data, res) = try await call(req)
        if res.statusCode == 409, Self.summary(data).hasPrefix("path/not_found") { return nil }
        try Self.check(data, res)
        let meta = (res.value(forHTTPHeaderField: "Dropbox-API-Result")?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        guard let rev = meta?["rev"] as? String else { throw Failure.server("응답을 읽지 못했어요") }
        return (data, rev)
    }

    /// rev 가 지금 판과 같을 때만 쓴다 (nil 이면 새로 만들기). 어긋나면 nil
    func write(_ body: Data, rev: String?) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        req.httpMethod = "POST"
        let mode: Any = rev.map { [".tag": "update", "update": $0] } ?? [".tag": "add"]
        req.setValue(Self.json(["path": Self.path, "mode": mode, "autorename": false, "mute": true, "strict_conflict": true]), forHTTPHeaderField: "Dropbox-API-Arg")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, res) = try await call(req)
        if res.statusCode == 409, Self.summary(data).contains("conflict") { return nil }
        try Self.check(data, res)
        guard let r = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["rev"] as? String else { throw Failure.server("응답을 읽지 못했어요") }
        return r
    }

    // MARK: 바뀌면 바로 알기 (롱폴링)

    func latestCursor() async throws -> String {
        let (data, res) = try await rpc("files/list_folder/get_latest_cursor", ["path": ""])
        try Self.check(data, res)
        guard let c = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["cursor"] as? String else { throw Failure.server("커서") }
        return c
    }

    /// 폴더가 바뀔 때까지 기다린다 (토큰이 필요 없다)
    func waitForChange(cursor: String, timeout: Int = 120) async throws -> (changes: Bool, backoff: Int?) {
        var req = URLRequest(url: URL(string: "https://notify.dropboxapi.com/2/files/list_folder/longpoll")!)
        req.httpMethod = "POST"
        req.timeoutInterval = TimeInterval(timeout + 90)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(Self.json(["cursor": cursor, "timeout": timeout]).utf8)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw Failure.server("응답 없음") }
        try Self.check(data, http)
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (j["changes"] as? Bool ?? false, j["backoff"] as? Int)
    }

    /// 바뀐 걸 읽어 커서를 앞으로 옮긴다
    func advance(cursor: String) async throws -> String {
        var c = cursor
        while true {
            let (data, res) = try await rpc("files/list_folder/continue", ["cursor": c])
            if res.statusCode == 409, Self.summary(data).hasPrefix("reset") { return try await latestCursor() }
            try Self.check(data, res)
            let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            guard let next = j["cursor"] as? String else { throw Failure.server("커서") }
            c = next
            if j["has_more"] as? Bool != true { return c }
        }
    }

    // MARK: 요청

    private func tokenRequest(_ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, res) = try await URLSession.shared.data(for: req)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400 || code == 401 { throw Failure.notConnected }
        guard code == 200, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.server("\(code)") }
        return j
    }

    private func token(force: Bool) async throws -> String {
        if !force, let a = access, Date() < a.until { return a.token }
        guard let r = SyncKeychain.read(.dropboxRefresh), let refresh = String(data: r, encoding: .utf8) else { throw Failure.notConnected }
        do {
            let j = try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": appKey])
            guard let t = j["access_token"] as? String else { throw Failure.server("토큰") }
            access = (t, Date().addingTimeInterval(Double(j["expires_in"] as? Int ?? 3600) - 60))
            return t
        } catch Failure.notConnected {
            SyncKeychain.delete(.dropboxRefresh)
            access = nil
            throw Failure.notConnected
        }
    }

    /// 토큰을 붙여 부른다. 401 이면 토큰을 새로 받아 한 번 더
    private func call(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0..<2 {
            var req = request
            req.setValue("Bearer \(try await token(force: attempt > 0))", forHTTPHeaderField: "Authorization")
            let (data, res) = try await URLSession.shared.data(for: req)
            guard let http = res as? HTTPURLResponse else { throw Failure.server("응답 없음") }
            if http.statusCode != 401 { return (data, http) }
        }
        SyncKeychain.delete(.dropboxRefresh)
        access = nil
        throw Failure.notConnected
    }

    private func rpc(_ endpoint: String, _ body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/" + endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(Self.json(body).utf8)
        return try await call(req)
    }

    private static func check(_ data: Data, _ res: HTTPURLResponse) throws {
        guard (200..<300).contains(res.statusCode) else {
            let s = summary(data)
            throw Failure.server(s.isEmpty ? "\(res.statusCode)" : s)
        }
    }

    private static func summary(_ data: Data) -> String {
        ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_summary"] as? String) ?? ""
    }

    /// 드롭박스 인자 헤더는 ASCII 만 받으므로 한글 등은 \u 로 바꾼다
    private static func json(_ obj: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s.unicodeScalars.map { $0.isASCII ? String($0) : String(format: "\\u%04x", $0.value) }.joined()
    }

    private static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func randomText(_ n: Int) -> String {
        var d = Data(count: n)
        d.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }
        return b64url(d)
    }
}

/// 로그인 창을 띄울 창 (미리 잡아 둔다)
private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    init(window: UIWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}

/// 동기화 비밀값 (드롭박스 갱신 토큰, 동기화 키). 이 기기에만 두고 백업·iCloud 키체인으로 넘기지 않는다
enum SyncKeychain {
    enum Slot: String { case dropboxRefresh = "dropbox.refresh", vaultKey = "sync.key" }
    private static let service = "com.kkkougaa.hikidashi.sync"

    private static func query(_ s: Slot) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: s.rawValue]
    }

    static func read(_ s: Slot) -> Data? {
        var q = query(s)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func write(_ s: Slot, _ data: Data) {
        let q = query(s)
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ s: Slot) {
        SecItemDelete(query(s) as CFDictionary)
    }
}
