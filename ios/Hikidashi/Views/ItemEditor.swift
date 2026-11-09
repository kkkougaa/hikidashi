import SwiftUI
import HikidashiCore

/// 새 항목 / 항목 편집. 왼쪽 ✕, 가운데 링크·메모 전환, 오른쪽 ✓ (캘린더 앱 시트처럼)
struct ItemEditor: View {
    let request: EditorRequest
    let defaultFolderId: String?
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ItemKind = .link
    @State private var url = ""
    @State private var title = ""
    @State private var note = ""
    @State private var image: String?
    @State private var video: String?
    @State private var avatar: String?
    @State private var images: [String] = []
    @State private var siteName: String?
    @State private var emoji: String?
    @State private var folderId: String?
    @State private var tags: [String] = []
    @State private var error: String?
    @State private var fetching = false
    @State private var fetchFailed = false
    @State private var saveWhenReady = false
    @State private var showEmoji = false
    @State private var touchedTitle = false
    @State private var touchedNote = false
    @State private var lastFetched: String?
    @FocusState private var focus: Field?

    enum Field { case title, url, note }

    private var editing: Item? { request.editing }
    private var normalized: String? { kind == .link ? normalizeURL(url) : nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField(kind == .link ? "제목" : "새로운 메모", text: $title, axis: .vertical)
                        .font(.title2.weight(.semibold))
                        .focused($focus, equals: .title)
                        .onChange(of: title) { if focus == .title { touchedTitle = true } }

                    if kind == .link { urlField }

                    TextField(kind == .link ? "내용 (페이지 소개문이 자동으로 들어가요)" : "메모", text: $note, axis: .vertical)
                        .font(.body)
                        .lineLimit(kind == .link ? 2...8 : 5...20)
                        .focused($focus, equals: .note)
                        .onChange(of: note) { if focus == .note { touchedNote = true } }
                    if kind == .memo, let error { Text(error).font(.footnote.weight(.semibold)).foregroundStyle(.red) }

                    VStack(spacing: 0) {
                        folderRow
                        Divider()
                        TagField(tags: $tags, suggestions: store.library.tagsByUse, sourceURL: normalized, siteName: siteName)
                            .padding(.vertical, 12)
                        Divider()
                        iconRow
                        if showEmoji {
                            EmojiGrid(selection: $emoji, autoLabel: kind == .link ? "자동 (글 이미지나 사이트 로고)" : "기본 (메모 아이콘)")
                                .padding(.bottom, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("닫기")
                }
                ToolbarItem(placement: .principal) {
                    if editing == nil {
                        Picker("종류", selection: $kind) {
                            Text("링크").tag(ItemKind.link)
                            Text("메모").tag(ItemKind.memo)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    } else {
                        Text("항목 편집").font(.headline)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { submit() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel(editing != nil ? "변경 사항 저장" : kind == .link ? "링크 저장" : "메모 저장")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: setup)
        .task(id: url) {
            // 주소를 적고 잠시 멈추면 자동으로 가져온다
            guard editing == nil, kind == .link, normalized != nil else { return }
            try? await Task.sleep(for: .milliseconds(url == request.prefill?.url ? 0 : 700))
            if !Task.isCancelled { await load(url) }
        }
    }

    // MARK: 칸들

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("주소 붙여넣기", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .url)
                    .onChange(of: url) { error = nil }
                // 애플 기본 붙여넣기 버튼: 권한 묻는 창 없이 바로 붙는다
                PasteButton(payloadType: String.self) { strings in
                    guard let s = strings.first else { return }
                    url = (findURL(in: s) ?? s).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            }
            .padding(.leading, 14).padding(.trailing, 6)
            .frame(minHeight: 52)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(error != nil ? Color.red : .clear, lineWidth: 1.5))

            Group {
                if let error {
                    Text(error).foregroundStyle(.red).fontWeight(.semibold)
                } else if fetching {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(saveWhenReady ? "페이지 정보를 받는 대로 저장할게요" : "페이지 정보를 가져오는 중") }
                } else if fetchFailed {
                    HStack { Text("페이지 정보를 가져오지 못했어요"); Button("다시 시도") { Task { await load(url, force: true) } } }
                } else if editing != nil, normalized != nil {
                    Button { Task { await load(url, force: true) } } label: { Label("페이지 정보 다시 가져오기", systemImage: "arrow.clockwise") }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var folderRow: some View {
        HStack {
            Text("서랍")
            Spacer()
            Picker("서랍", selection: $folderId) {
                ForEach(store.pickFolders) { f in
                    Label { Text(f.name) } icon: { Image(systemName: "folder.fill").foregroundStyle(f.color.color) }.tag(Optional(f.id))
                }
                Divider()
                Text("미분류").tag(String?.none)
            }
            .pickerStyle(.menu)
            .tint(.secondary)
        }
        .frame(minHeight: 52)
    }

    private var iconRow: some View {
        Button {
            withAnimation(.snappy) { showEmoji.toggle() }
        } label: {
            HStack {
                Text("아이콘").foregroundStyle(.primary)
                Spacer()
                if let emoji { Text(emoji).font(.title2) } else { Text(kind == .memo ? "기본" : "자동").foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(showEmoji ? 90 : 0))
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: 동작

    private func setup() {
        let src = editing.map { ItemDraft(kind: $0.kind, url: $0.url, title: $0.title, note: $0.note, image: $0.image, siteName: $0.siteName, emoji: $0.emoji, folderId: $0.folderId, tags: $0.tags) }
            ?? request.prefill
        kind = src?.kind ?? .link
        url = src?.url ?? ""
        title = src?.title ?? ""
        note = src?.note ?? ""
        image = src?.image
        video = editing?.video
        avatar = editing?.avatar
        images = editing?.images ?? []
        siteName = src?.siteName
        emoji = src?.emoji
        folderId = editing != nil ? editing?.folderId : (src?.folderId ?? defaultFolderId)
        tags = src?.tags ?? []
        touchedTitle = !title.isEmpty
        touchedNote = !note.isEmpty
        lastFetched = editing?.url
    }

    private func load(_ raw: String, force: Bool = false) async {
        guard let u = normalizeURL(raw), force || lastFetched != u else { return }
        lastFetched = u
        fetching = true
        fetchFailed = false
        let info = await store.fetchInfo(u)
        guard normalizeURL(url) == u else { return } // 그사이 주소가 바뀜
        fetching = false
        if let info {
            withAnimation(.snappy) {
                if let t = info.title, force || !touchedTitle { title = t }
                if let d = info.description, force || !touchedNote { note = d }
                image = info.image
                video = info.video
                avatar = info.avatar
                images = info.images
                siteName = info.siteName
            }
        } else {
            fetchFailed = true
        }
        if saveWhenReady { saveWhenReady = false; submit() }
    }

    private func submit() {
        let base = ItemDraft(kind: kind, title: title.trimmingCharacters(in: .whitespacesAndNewlines), note: note.trimmingCharacters(in: .whitespacesAndNewlines), emoji: emoji, folderId: folderId, tags: tags)
        var d = base
        if kind == .link {
            guard !url.trimmingCharacters(in: .whitespaces).isEmpty else { error = "저장할 주소를 넣어주세요"; return }
            guard let u = normalizeURL(url) else { error = "주소 형식을 확인해주세요. 예: example.com/article"; return }
            if editing == nil, fetching || lastFetched != u {
                saveWhenReady = true
                if !fetching { Task { await load(u) } }
                return
            }
            d.url = u
            d.image = image
            d.video = video
            d.avatar = avatar
            d.images = images
            d.siteName = siteName
            // 내용이 있으면 제목을 지어내지 않고 비워 둔다 (X 게시물 같은 경우)
            if d.title.isEmpty, d.note.isEmpty { d.title = guessTitle(u) }
        } else {
            guard !d.note.isEmpty || !d.title.isEmpty else { error = "메모 내용을 적어주세요"; return }
        }
        if let editing { store.apply(d, to: editing.id) } else { store.add(d) }
        dismiss()
    }
}

/// 태그 칩 입력: 스페이스·쉼표·엔터로 칩이 되고, 없는 태그는 새로 만든다
struct TagField: View {
    @Binding var tags: [String]
    let suggestions: [String]
    var sourceURL: String?
    var siteName: String?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("태그")
            FlowLayout(spacing: 6) {
                if let sourceURL { SourceChip(url: sourceURL, siteName: siteName) }
                ForEach(tags, id: \.self) { t in
                    HStack(spacing: 2) {
                        Text("#\(t)")
                        Button { withAnimation(.snappy) { tags.removeAll { $0 == t } } } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                            .accessibilityLabel("\(t) 태그 빼기")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brand)
                    .padding(.leading, 10).padding(.trailing, 8).frame(height: 30)
                    .background(Color.brand.opacity(0.12), in: .rect(cornerRadius: 8))
                }
                TextField(tags.isEmpty ? "태그 입력 후 스페이스" : "", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .frame(minWidth: 80)
                    .frame(height: 30)
                    .onChange(of: text) { split() }
                    .onSubmit { commit(text); text = "" ; focused = true }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))
            .onTapGesture { focused = true }

            let q = normalizeTag(text).lowercased()
            let picks = suggestions.filter { !tags.contains($0) && (q.isEmpty || $0.lowercased().contains(q)) }.prefix(8)
            let isNew = !q.isEmpty && !suggestions.contains { $0.lowercased() == q } && !tags.contains(normalizeTag(text))
            if !picks.isEmpty || isNew {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if isNew {
                            Button { commit(text); text = "" } label: { Label("새 태그 #\(normalizeTag(text))", systemImage: "plus") }
                                .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 8)).tint(Color.brand)
                        }
                        ForEach(Array(picks), id: \.self) { s in
                            Button("#\(s)") { commit(s); text = "" }
                                .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 8)).tint(.secondary)
                        }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private func split() {
        let seps = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，"))
        guard text.rangeOfCharacter(from: seps) != nil else { return }
        var parts = text.components(separatedBy: seps)
        let rest = parts.removeLast()
        parts.forEach(commit)
        text = rest
    }

    private func commit(_ raw: String) {
        let t = normalizeTag(raw)
        guard !t.isEmpty, !tags.contains(t) else { return }
        withAnimation(.snappy) { tags.append(t) }
    }
}

/// 아이콘 이모지 고르기
struct EmojiGrid: View {
    @Binding var selection: String?
    let autoLabel: String

    static let groups: [(String, [String])] = [
        ("정리", ["📌", "📎", "🔖", "📚", "📖", "📝", "✏️", "💡", "⭐", "❤️", "🔥", "✅", "❗", "❓", "🎯", "🏷️"]),
        ("생활", ["🛒", "🍳", "🍜", "🍕", "☕", "🍰", "🏠", "🧺", "💊", "💪", "🏃", "🧘", "🛏️", "🧹", "👕", "🐶"]),
        ("여행", ["✈️", "🗺️", "🏖️", "🏔️", "🚗", "🚆", "🏨", "📷", "🎒", "🌏", "🍣", "🗼"]),
        ("일·공부", ["💻", "📱", "🖥️", "💼", "📊", "📈", "🗂️", "📅", "⏰", "🎓", "🧠", "🔧", "⚙️", "🧪", "📮", "🗒️"]),
        ("취미", ["🎵", "🎬", "🎮", "🎨", "📺", "🎧", "⚽", "🏀", "🎁", "🎉", "🧩", "🎸"]),
        ("기분", ["😀", "😂", "🥹", "😍", "🤔", "😎", "🥳", "😴", "👍", "👀", "🙏", "✨"]),
        ("자연·돈", ["🌱", "🌸", "🍀", "🌙", "☀️", "🌈", "🐱", "🐳", "💰", "💳", "🧾", "🏦"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { selection = nil } label: {
                Label(autoLabel, systemImage: selection == nil ? "checkmark" : "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered).tint(selection == nil ? Color.brand : .secondary)
            ForEach(Self.groups, id: \.0) { name, list in
                Text(name).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
                    ForEach(list, id: \.self) { e in
                        Button { selection = selection == e ? nil : e } label: {
                            Text(e).font(.system(size: 28)).frame(width: 44, height: 44)
                                .background(selection == e ? Color.brand.opacity(0.15) : .clear, in: .rect(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selection == e ? Color.brand : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(e)
                        .accessibilityAddTraits(selection == e ? .isSelected : [])
                    }
                }
            }
        }
    }
}
