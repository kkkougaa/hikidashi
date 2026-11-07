import SwiftUI
import UIKit
import UniformTypeIdentifiers
import HikidashiCore

/// 공유 시트에서 hikidashi 를 누르면: 링크(또는 글)를 받아 페이지 정보를 채워 바로 저장하고 닫는다
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { @MainActor in
            await model.run(items)
            try? await Task.sleep(for: .seconds(model.state.isError ? 1.8 : 0.9))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

@MainActor
@Observable
final class ShareModel {
    enum State {
        case saving, saved(title: String, folder: String), duplicate, failed(String)
        var isError: Bool { if case .failed = self { true } else { false } }
    }

    var state: State = .saving

    func run(_ items: [NSExtensionItem]) async {
        let (url, text) = await Self.extract(items)
        var lib = SharedLibrary.load() ?? .seeded()
        let folderId = SharedLibrary.defaultFolderId(in: lib)
        let folderName = lib.folder(folderId)?.name ?? "미분류"

        var draft: ItemDraft
        if let url {
            if lib.contains(url: url) { state = .duplicate; return }
            draft = ItemDraft(kind: .link, url: url, folderId: folderId)
            // 정보는 기다릴 만큼만 (공유 시트를 오래 붙잡지 않게)
            if let info = await PageInfoFetcher(timeout: 6).fetch(url) {
                draft.title = info.title ?? ""
                draft.note = info.description ?? ""
                draft.image = info.image
                draft.siteName = info.siteName
            }
            if draft.title.isEmpty, draft.note.isEmpty { draft.title = guessTitle(url) }
        } else if let text, !text.isEmpty {
            draft = ItemDraft(kind: .memo, note: text, folderId: folderId)
        } else {
            state = .failed("저장할 링크나 글을 찾지 못했어요")
            return
        }

        // 그사이 앱이 바꿨을 수 있으니 저장 직전에 다시 읽는다
        lib = SharedLibrary.load() ?? lib
        let item = lib.addItem(draft)
        do {
            try SharedLibrary.save(lib)
            state = .saved(title: item.displayTitle, folder: folderName)
        } catch {
            state = .failed("저장하지 못했어요")
        }
    }

    /// 공유된 것에서 웹 주소를 먼저, 없으면 글을 꺼낸다
    static func extract(_ items: [NSExtensionItem]) async -> (url: String?, text: String?) {
        var text: String?
        for item in items {
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let v = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) {
                    let u = (v as? URL) ?? (v as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (v as? String).flatMap(URL.init(string:))
                    if let u, !u.isFileURL, let n = normalizeURL(u.absoluteString) { return (n, nil) }
                }
                if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let v = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                    let s = (v as? String) ?? (v as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    if let s {
                        if let u = normalizeURL(s) ?? findURL(in: s) { return (u, nil) }
                        text = text ?? s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            if text == nil, let t = item.attributedContentText?.string, !t.isEmpty {
                if let u = findURL(in: t) { return (u, nil) }
                text = t
            }
        }
        return (nil, text)
    }
}

/// 아래쪽에 잠깐 뜨는 저장 카드
struct ShareCard: View {
    let model: ShareModel
    private let brand = Color(red: 0x13 / 255, green: 0x66 / 255, blue: 0xE0 / 255)

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                icon.frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.headline)
                    if let sub { Text(sub).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(.regularMaterial, in: .rect(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(.horizontal, 16).padding(.bottom, 24)
            .animation(.snappy, value: headline)
        }
    }

    @ViewBuilder private var icon: some View {
        switch model.state {
        case .saving: ProgressView().controlSize(.large).tint(brand)
        case .saved: Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(brand).transition(.scale)
        case .duplicate: Image(systemName: "bookmark.circle.fill").font(.system(size: 34)).foregroundStyle(.secondary)
        case .failed: Image(systemName: "exclamationmark.circle.fill").font(.system(size: 34)).foregroundStyle(.red)
        }
    }

    private var headline: String {
        switch model.state {
        case .saving: "hikidashi 에 저장 중…"
        case .saved: "저장했어요"
        case .duplicate: "이미 저장한 링크예요"
        case .failed(let m): m
        }
    }

    private var sub: String? {
        switch model.state {
        case .saved(let title, let folder): "\(folder) · \(title)"
        default: nil
        }
    }
}
