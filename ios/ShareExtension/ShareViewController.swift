import SwiftUI
import UIKit
import UniformTypeIdentifiers
import HikidashiCore

/// 공유 시트에서 hikidashi 를 누르면 뜨는 작은 카드.
/// 그대로 두면 잠시 뒤 기본 서랍에 저장되고, 서랍·태그·제목을 만지면 기다렸다가 "저장" 을 누를 때 저장한다
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        model.onFinish = { [weak self] saved in
            guard let ctx = self?.extensionContext else { return }
            if saved {
                ctx.completeRequest(returningItems: nil)
            } else {
                ctx.cancelRequest(withError: NSError(domain: "hikidashi", code: 0))
            }
        }
        let host = UIHostingController(rootView: ShareCard(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        model.start(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
    }
}

@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable { case reading, ready, saving, saved, failed(String) }

    var phase: Phase = .reading
    var url: String?
    var text: String?
    var info: PageInfo?
    var loadingInfo = false
    var title = ""
    var folders: [ShareInbox.Context.FolderInfo] = []
    var suggestions: [String] = []
    /// "none" 이면 미분류
    var folderChoice: String?
    var tags: [String] = []
    var tagInput = ""
    /// 손대지 않으면 저절로 저장되기까지 (0…1)
    var autoProgress: Double = 0
    var touched = false

    var onFinish: (Bool) -> Void = { _ in }
    private var infoTask: Task<PageInfo?, Never>?
    static let autoSeconds = 3.0

    var isMemo: Bool { url == nil }

    func start(_ items: [NSExtensionItem]) {
        let ctx = ShareInbox.readContext()
        folders = ctx?.folders ?? []
        suggestions = ctx?.tags ?? []
        folderChoice = ctx?.defaultFolderId ?? folders.first?.id ?? "none"
        Task {
            let (u, t) = await Self.extract(items)
            url = u
            text = t
            guard u != nil || !(t ?? "").isEmpty else {
                phase = .failed("저장할 링크나 글을 찾지 못했어요")
                try? await Task.sleep(for: .seconds(1.6))
                onFinish(false)
                return
            }
            phase = .ready
            if let u {
                loadingInfo = true
                // 정보는 기다릴 만큼만 (공유 시트를 오래 붙잡지 않게)
                let task = Task { await PageInfoFetcher(timeout: 6).fetch(u) }
                infoTask = task
                let got = await task.value
                info = got
                loadingInfo = false
                if !touched || title.isEmpty { title = got?.title ?? "" }
            }
        }
        Task { await countdown() }
    }

    private func countdown() async {
        let step = 0.05
        while autoProgress < 1 {
            try? await Task.sleep(for: .seconds(step))
            if touched || phase != .ready && phase != .reading { return }
            if phase == .ready { autoProgress = min(1, autoProgress + step / Self.autoSeconds) }
        }
        await save()
    }

    func touch() {
        guard !touched else { return }
        withAnimation(.snappy) { touched = true; autoProgress = 0 }
    }

    func addTag(_ raw: String) {
        for t in parseTags(raw) where !tags.contains(t) { tags.append(t) }
        tagInput = ""
    }

    func save() async {
        guard phase == .ready else { return }
        phase = .saving
        if !tagInput.isEmpty { addTag(tagInput) }
        var draft: ItemDraft
        if let url {
            let got = await infoTask?.value ?? info
            draft = ItemDraft(kind: .link, url: url)
            draft.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.title.isEmpty { draft.title = got?.title ?? "" }
            draft.note = got?.description ?? ""
            draft.image = got?.image
            draft.siteName = got?.siteName
            if draft.title.isEmpty, draft.note.isEmpty { draft.title = guessTitle(url) }
        } else {
            draft = ItemDraft(kind: .memo, title: title.trimmingCharacters(in: .whitespacesAndNewlines), note: text ?? "")
        }
        // 앱 우편함에 넣어 두면, 앱을 열 때 고른 서랍으로 들어간다
        if ShareInbox.put(draft, folderChoice: folderChoice, tags: tags) {
            withAnimation(.snappy) { phase = .saved }
            try? await Task.sleep(for: .seconds(0.7))
            onFinish(true)
        } else {
            phase = .failed("저장하지 못했어요")
            try? await Task.sleep(for: .seconds(1.6))
            onFinish(false)
        }
    }

    func cancel() { onFinish(false) }

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
                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        // 주소 하나만 있으면 링크, 글 사이에 주소가 섞였으면 글을 메모로
                        if let u = normalizeURL(trimmed) { return (u, nil) }
                        text = text ?? trimmed
                    }
                }
            }
            if text == nil, let t = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                if let u = normalizeURL(t) { return (u, nil) }
                text = t
            }
        }
        // 글만 왔는데 그 안에 주소 하나가 거의 전부면 링크로
        if let t = text, let u = findURL(in: t), t.count - u.count < 12 { return (u, nil) }
        return (nil, text)
    }
}

private let brand = Color(red: 0x13 / 255, green: 0x66 / 255, blue: 0xE0 / 255)

private func hexColor(_ hex: String) -> Color {
    let v = Int(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

struct ShareCard: View {
    @Bindable var model: ShareModel
    @FocusState private var focus: Field?
    enum Field { case title, tag }

    var body: some View {
        VStack {
            Spacer()
            Group {
                switch model.phase {
                case .saved: status("checkmark.circle.fill", "hikidashi 에 넣었어요", color: brand)
                case .failed(let m): status("exclamationmark.circle.fill", m, color: .red)
                case .reading: status(nil, "읽는 중…", color: brand)
                default: editor
                }
            }
            .padding(18)
            .background(.regularMaterial, in: .rect(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(.horizontal, 12).padding(.bottom, 12)
            .animation(.snappy, value: model.phase)
        }
        .onChange(of: focus) { _, f in if f != nil { model.touch() } }
    }

    private func status(_ icon: String?, _ text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            if let icon { Image(systemName: icon).font(.system(size: 30)).foregroundStyle(color) } else { ProgressView().controlSize(.large) }
            Text(text).font(.headline)
            Spacer(minLength: 0)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 미리보기 + 제목
            HStack(alignment: .top, spacing: 12) {
                thumb.frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    TextField(model.isMemo ? "제목 (없어도 돼요)" : (model.loadingInfo ? "제목 불러오는 중…" : "제목"), text: $model.title, axis: .vertical)
                        .font(.headline).lineLimit(1...2)
                        .focused($focus, equals: .title)
                    if let url = model.url {
                        Text(model.info?.siteName ?? domain(of: url)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    } else if let t = model.text {
                        Text(t).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }

            // 서랍 고르기
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.folders) { f in chip(f.name, color: hexColor(f.hex), on: model.folderChoice == f.id) { model.folderChoice = f.id } }
                    chip("미분류", color: .gray, on: model.folderChoice == "none") { model.folderChoice = "none" }
                }
            }

            // 태그
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.tags, id: \.self) { t in
                            Button { model.touch(); model.tags.removeAll { $0 == t } } label: {
                                HStack(spacing: 3) { Text("#\(t)"); Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).frame(height: 30)
                                    .background(brand, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                        TextField(model.tags.isEmpty ? "태그 (스페이스로 추가)" : "태그", text: $model.tagInput)
                            .font(.subheadline).frame(minWidth: 120)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focus, equals: .tag)
                            .onSubmit { model.addTag(model.tagInput); focus = .tag }
                            .onChange(of: model.tagInput) { _, v in if v.last == " " || v.last == "," { model.addTag(v) } }
                    }
                }
                let rest = model.suggestions.filter { !model.tags.contains($0) }.prefix(12)
                if !rest.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(rest), id: \.self) { t in
                                Button { model.touch(); model.addTag(t) } label: {
                                    Text("#\(t)").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 9).frame(height: 26)
                                        .background(Color(.tertiarySystemFill), in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // 버튼
            HStack(spacing: 10) {
                Button { model.cancel() } label: { Text("취소").frame(maxWidth: .infinity, minHeight: 48) }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                Button { Task { await model.save() } } label: {
                    HStack(spacing: 8) {
                        if model.phase == .saving {
                            ProgressView().tint(.white)
                        } else if !model.touched {
                            // 저절로 저장되기까지 남은 시간
                            Circle().trim(from: 0, to: model.autoProgress)
                                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .background(Circle().stroke(.white.opacity(0.3), lineWidth: 2.5))
                                .frame(width: 16, height: 16)
                        }
                        Text(model.phase == .saving ? "저장 중…" : "저장")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(brand)
                .disabled(model.phase == .saving)
            }
            if !model.touched {
                Text("그대로 두면 잠시 뒤 저장돼요. 서랍이나 태그를 만지면 기다려요.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var thumb: some View {
        if let img = model.info?.image, let u = URL(string: img) {
            AsyncImage(url: u) { p in
                if case .success(let i) = p { i.resizable().scaledToFill() } else { Color(.tertiarySystemFill) }
            }
        } else if let url = model.url, let logo = logoURL(url, size: 128).flatMap(URL.init(string:)) {
            AsyncImage(url: logo) { p in
                if case .success(let i) = p { i.resizable().scaledToFit().padding(10) } else { Color.clear }
            }
            .background(Color(.systemBackground))
            .overlay { if model.loadingInfo { ProgressView() } }
        } else {
            Image(systemName: "note.text").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(brand)
        }
    }

    private func chip(_ name: String, color: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button { model.touch(); action() } label: {
            HStack(spacing: 6) {
                Circle().fill(on ? .white : color).frame(width: 8, height: 8)
                Text(name).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? .white : .primary)
            .padding(.horizontal, 12).frame(height: 34)
            .background(on ? color : Color(.tertiarySystemFill), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
