import UniformTypeIdentifiers
import SwiftUI
import HikidashiCore

/// 왼쪽에서 나오는 서랍: 보관함, 서랍(색), 태그, 설정
struct DrawerView: View {
    let selected: Scope
    var onSelect: (Scope) -> Void
    var onSettings: () -> Void
    var onOpen: (Item) -> Void = { _ in }
    @Environment(LibraryStore.self) private var store
    @State private var editing: FolderEdit?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("hikidashi").font(.title2.weight(.bold))
                    Spacer()
                    // NSFW 태그 항목 보이기·숨기기 (이 기기만)
                    Button { withAnimation(.snappy) { store.toggleShowNsfw() } } label: {
                        Image(systemName: store.showNsfw ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(store.showNsfw ? Color.brand : .secondary)
                            .frame(width: 40, height: 40)
                            .background(Color(.tertiarySystemFill), in: .circle)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.showNsfw ? "NSFW 숨기기" : "NSFW 보이기")
                    // 설정은 하단바로 옮겼다
                }
                .padding(.leading, 12).padding(.trailing, 4)
                .padding(.bottom, 14)

                row(.all, "전체", icon: "tray.fill", color: .brand, count: store.activeItems.count)
                let memos = store.items(in: .memos).count
                if memos > 0 { row(.memos, "메모", icon: "note.text", color: FolderColor.teal.color, count: memos) }
                row(.starred, "즐겨찾기", icon: "star.fill", color: FolderColor.mustard.color, count: store.activeItems.filter(\.starred).count)
                let unfiled = store.items(in: .unfiled).count
                if unfiled > 0 { row(.unfiled, "미분류", icon: "archivebox.fill", color: unfiledColor, count: unfiled) }
                let marked = store.items(in: .highlights).count
                if marked > 0 { row(.highlights, "하이라이트", icon: "highlighter", color: Color(hex: "#C99700"), count: marked) }
                let broken = store.items(in: .broken).count
                if broken > 0 { row(.broken, "열리지 않는 링크", icon: "link", color: .red, count: broken) }
                let done = store.items(in: .done).count
                if done > 0 { row(.done, "완료함", icon: "checkmark.circle.fill", color: .green, count: done) }

                // 최근 연 항목
                let recent = Array(store.recentItems.prefix(5))
                if !recent.isEmpty {
                    header("최근 연 항목") { EmptyView() }
                    ForEach(recent) { it in
                        Button { onOpen(it) } label: {
                            HStack(spacing: 12) {
                                ItemIcon(item: it, folder: store.folder(it.folderId), size: 28)
                                Text(it.displayTitle).font(.subheadline).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).frame(height: 42)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }

                header("서랍") {
                    Button { editing = FolderEdit(folder: nil) } label: {
                        Image(systemName: "plus").font(.subheadline.weight(.bold)).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("새 서랍")
                }
                ForEach(store.library.orderedFolders, id: \.folder.id) { entry in
                    let f = entry.folder
                    row(.folder(f.id), f.name, icon: entry.depth > 0 ? "folder" : "folder.fill",
                        color: store.library.displayColor(f).color, count: store.count(inFolder: f.id), indent: entry.depth > 0)
                        .contextMenu {
                            Button { editing = FolderEdit(folder: f) } label: { Label("편집", systemImage: "pencil") }
                            Button(role: .destructive) {
                                if selected == .folder(f.id) { onSelect(.all) }
                                store.removeFolder(f)
                            } label: { Label("삭제", systemImage: "trash") }
                        }
                }

                let tags = store.showNsfw ? store.library.tagCounts : store.library.tagCounts.filter { $0.tag.lowercased() != Library.nsfwTag }
                if !tags.isEmpty {
                    header("태그") { EmptyView() }
                    ForEach(tags, id: \.tag) { t in
                        row(.tag(t.tag), t.tag, icon: "number", color: nil, count: t.count)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editing) { FolderEditor(folder: $0.folder) }
    }

    private func header<T: View>(_ title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.leading, 12).padding(.trailing, 4)
        .padding(.top, 18).padding(.bottom, 4)
        .frame(minHeight: 32)
    }

    private func row(_ scope: Scope, _ name: String, icon: String, color: Color?, count: Int, indent: Bool = false) -> some View {
        let on = selected == scope
        return Button { onSelect(scope) } label: {
            HStack(spacing: 12) {
                if let color, indent {
                    // 하위 서랍: 들여 쓰고 작게
                    Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                        .frame(width: 28, height: 28)
                        .padding(.leading, 18)
                } else if let color {
                    Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(color, in: .rect(cornerRadius: 8))
                } else {
                    Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).frame(width: 28)
                }
                Text(name).font(.body.weight(on ? .semibold : .regular)).lineLimit(1)
                Spacer()
                Text("\(count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 10).frame(height: 46)
            .background(on ? Color.brand.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue("\(count)개")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 설정: 화면, 새 항목, 정리(서랍·태그), 백업, 정보
struct SettingsScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("viewMode") private var viewMode = "list"
    @AppStorage("groupBy") private var groupBy = "day"
    @AppStorage("linkOpen") private var linkOpen = "reader"
    @AppStorage("saveArticles") private var saveArticles = true
    @State private var cacheSize = 0
    @State private var syncPass = ""
    @State private var syncPassAgain = ""
    @State private var syncPassError: String?
    @State private var checkingPass = false
    @State private var articleCount = 0
    @AppStorage(SharedLibrary.defaultFolderKey) private var defaultFolder = ""
    @AppStorage("lastBackupAt") private var lastBackup: Double = 0
    @State private var backupURL: URL?
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("화면") {
                    Picker("화면 모드", selection: $appearance) {
                        Text("시스템").tag("system")
                        Text("라이트").tag("light")
                        Text("다크").tag("dark")
                    }
                    Picker("기본 보기", selection: $viewMode) {
                        Text("타임라인").tag("list")
                        Text("미디어").tag("grid")
                    }
                    Picker("목록 묶음", selection: $groupBy) {
                        Text("날짜").tag("day")
                        Text("사이트").tag("site")
                    }
                }
                Section {
                    Picker("링크를 누르면", selection: $linkOpen) {
                        Text("리더 모드").tag("reader")
                        Text("사파리").tag("safari")
                    }
                    Toggle("새 글 본문 미리 저장", isOn: $saveArticles)
                } footer: { Text("리더 모드는 광고와 메뉴 없이 본문만 보여줘요. X 와 유튜브는 늘 원래 화면으로 열어요. 본문을 저장해 두면 원본이 지워져도, 인터넷이 없어도 읽을 수 있어요.") }
                Section {
                    Button { store.checkLinks(force: true) } label: {
                        HStack {
                            Label("지금 링크 점검", systemImage: "stethoscope")
                            Spacer()
                            if store.checkingLinks { ProgressView() }
                        }
                    }
                    .disabled(store.checkingLinks)
                    LabeledContent("열리지 않는 링크", value: "\(store.library.broken.count)개")
                    if let last = store.lastLinkCheck {
                        LabeledContent("마지막 점검", value: last.formatted(.relative(presentation: .named)))
                    }
                } header: { Text("링크 점검") } footer: { Text("하루에 한 번, 일주일 넘게 안 본 링크를 조금씩 확인해요. 지워진 페이지(404)만 ‘안 열림’ 으로 표시하고, 잠깐 막힌 건 건드리지 않아요.") }
                Section("저장 공간") {
                    LabeledContent("썸네일", value: ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                    LabeledContent("저장한 본문", value: "\(articleCount)개")
                    Button("썸네일 비우기", role: .destructive) { ImageCache.clear(); cacheSize = 0 }
                    Button("저장한 본문 비우기", role: .destructive) { ArticleDisk.clear(); articleCount = 0 }
                }
                Section {
                    Picker("기본 서랍", selection: $defaultFolder) {
                        Text("첫 번째 서랍").tag("")
                        ForEach(store.pickFolders) { f in Text(f.name).tag(f.id) }
                        Text("미분류").tag("none")
                    }
                } header: { Text("새 항목") } footer: { Text("+ 버튼, 끌어올려 추가, 공유 시트로 넣은 항목이 들어갈 서랍이에요.") }
                Section("정리") {
                    NavigationLink { FolderManager() } label: {
                        LabeledContent { Text("\(store.folders.count)개") } label: { Label("서랍 관리", systemImage: "folder") }
                    }
                    NavigationLink { TagManager() } label: {
                        LabeledContent { Text("\(store.library.tagCounts.count)개") } label: { Label("태그 관리", systemImage: "number") }
                    }
                }
                Section {
                    switch store.syncState {
                    case .unset:
                        settingRow("동기화 꺼짐", hint: "이 빌드엔 드롭박스 설정이 없어요", icon: "icloud.slash")
                    case .off:
                        Button { Task { await store.connectDropbox() } } label: {
                            settingRow("드롭박스로 동기화", hint: "내용은 이 기기에서 잠가서 올려요", icon: "lock.icloud")
                        }
                    case .needsKey(let fresh, let note):
                        settingRow(fresh ? "동기화 암호 정하기" : "동기화 암호 넣기",
                                   hint: fresh ? "다른 기기에서도 이 암호를 넣어요. 잊으면 드롭박스 사본은 열 수 없어요" : "처음 정한 동기화 암호를 넣어주세요",
                                   icon: "key")
                        SecureField(fresh ? "8자 이상" : "동기화 암호", text: $syncPass)
                            .textContentType(fresh ? .newPassword : .password)
                        if fresh {
                            SecureField("한 번 더", text: $syncPassAgain).textContentType(.newPassword)
                        }
                        if let msg = passProblem(fresh: fresh) ?? syncPassError ?? note {
                            Text(msg).font(.footnote).foregroundStyle(.red)
                        }
                        Button {
                            checkingPass = true
                            Task {
                                syncPassError = await store.submitPassphrase(syncPass)
                                checkingPass = false
                                if syncPassError == nil { syncPass = ""; syncPassAgain = "" }
                            }
                        } label: {
                            HStack {
                                Text(fresh ? "정하고 동기화" : "확인")
                                if checkingPass { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(checkingPass || !(fresh ? syncPass.count >= 8 && syncPass == syncPassAgain : !syncPass.isEmpty))
                        Button("연결 끊기", role: .destructive) { store.disconnectSync() }
                    default:
                        HStack {
                            Text("상태")
                            Spacer()
                            switch store.syncState {
                            case .syncing: ProgressView()
                            case .failed(let m): Text(m).foregroundStyle(.red).font(.footnote).multilineTextAlignment(.trailing)
                            case .idle(let last): Text(last.map { "\($0.formatted(.relative(presentation: .named))) 동기화" } ?? "아직 안 함").foregroundStyle(.secondary)
                            default: EmptyView()
                            }
                        }
                        Button { Task { await store.syncNow(quiet: false) } } label: { Label("지금 동기화", systemImage: "arrow.triangle.2.circlepath") }
                        Button("연결 끊기", role: .destructive) { store.disconnectSync() }
                    }
                } header: { Text("동기화 (드롭박스)") } footer: {
                    Text("항목은 이 기기에서 동기화 암호로 잠근 뒤 드롭박스 앱 폴더에 올려요. 드롭박스에서도 내용을 볼 수 없어요. 웹앱에서 같은 드롭박스와 암호로 연결하면 맞춰져요.")
                }
                Section("백업") {
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            settingRow("백업 파일 만들기", hint: lastBackup > 0 ? "마지막 백업 \(store.dates.stamp(Millis(lastBackup * 1000)))" : "아직 백업한 적이 없어요", icon: "square.and.arrow.down")
                        }
                        .simultaneousGesture(TapGesture().onEnded { lastBackup = Date().timeIntervalSince1970 })
                    }
                    Button { importing = true } label: {
                        settingRow("백업에서 가져오기", hint: "웹앱에서 내보낸 파일도 돼요. 같은 항목은 더 최근에 고친 쪽을 남겨요", icon: "square.and.arrow.up")
                    }
                }
                Section("정보") {
                    LabeledContent("저장 위치", value: "이 아이폰")
                    LabeledContent("항목", value: "\(store.allItems.count)개")
                    LabeledContent("버전", value: [
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).map { "(\($0))" },
                    ].compactMap { $0 }.joined(separator: " "))
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("설정 닫기")
                }
            }
            .task {
                backupURL = try? store.writeBackupFile()
                cacheSize = await Task.detached { ImageCache.diskSize() }.value
                articleCount = ArticleDisk.count
            }
            .onChange(of: store.allItems.count) { backupURL = try? store.writeBackupFile() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { store.importBackup(from: url) }
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
    }

    /// 새 암호를 정할 때 입력 확인
    private func passProblem(fresh: Bool) -> String? {
        guard fresh else { return nil }
        if !syncPass.isEmpty && syncPass.count < 8 { return "8자 이상으로 정해주세요" }
        if !syncPassAgain.isEmpty && syncPassAgain != syncPass { return "두 암호가 달라요" }
        return nil
    }

    private func settingRow(_ title: String, hint: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(Color.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

enum Appearance: String {
    case system, light, dark
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 서랍 관리: 순서 바꾸기, 고치기, 지우기
struct FolderManager: View {
    @Environment(LibraryStore.self) private var store
    @State private var editing: FolderEdit?

    var body: some View {
        List {
            Section {
                let rows = store.library.orderedFolders
                ForEach(rows, id: \.folder.id) { entry in
                    let f = entry.folder
                    Button { editing = FolderEdit(folder: f) } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 7).fill(store.library.displayColor(f).color).frame(width: 26, height: 26)
                                .overlay(Image(systemName: entry.depth > 0 ? "folder" : "folder.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                                .scaleEffect(entry.depth > 0 ? 0.8 : 1)
                            Text(f.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(store.count(inFolder: f.id))").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.leading, entry.depth > 0 ? 24 : 0)
                    }
                }
                .onMove { from, to in
                    // 같은 단계 안에서만 순서를 바꾼다 (다른 단계로 끌면 무시)
                    var list = rows
                    list.move(fromOffsets: from, toOffset: to)
                    guard let moved = from.first.map({ rows[$0].folder }) else { return }
                    let key = moved.parentId.flatMap { store.library.folder($0) }?.id
                    let ids = list.filter { $0.depth == (key == nil ? 0 : 1) && ($0.depth == 0 || $0.folder.parentId == key) }.map(\.folder.id)
                    store.reorderFolders(ids)
                }
                .onDelete { idx in idx.map { rows[$0].folder }.forEach { store.removeFolder($0) } }
            } footer: { Text("길게 눌러 끌면 같은 단계 안에서 순서가 바뀌어요. 지운 서랍(하위 서랍 포함)의 항목은 미분류로 가요.") }
            Button { editing = FolderEdit(folder: nil) } label: { Label("새 서랍", systemImage: "plus") }
        }
        .navigationTitle("서랍 관리")
        .toolbar { EditButton() }
        .sheet(item: $editing) { FolderEditor(folder: $0.folder) }
    }
}

/// 태그 관리: 이름 바꾸기(같은 이름이면 합치기), 지우기
struct TagManager: View {
    @Environment(LibraryStore.self) private var store
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        let tags = store.library.tagCounts
        List {
            if tags.isEmpty {
                ContentUnavailableView("태그가 없어요", systemImage: "number", description: Text("항목을 추가할 때 태그를 달면 여기서 정리할 수 있어요."))
            }
            Section {
                ForEach(tags, id: \.tag) { t in
                    Button { newName = t.tag; renaming = t.tag } label: {
                        HStack {
                            Text("#\(t.tag)").foregroundStyle(.primary)
                            Spacer()
                            Text("\(t.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { store.removeTag(t.tag) } label: { Label("삭제", systemImage: "trash") }
                    }
                }
            } footer: { if !tags.isEmpty { Text("눌러서 이름을 바꿔요. 이미 있는 이름으로 바꾸면 두 태그가 합쳐져요. 밀어서 지우면 항목에서 태그만 빠져요.") } }
        }
        .navigationTitle("태그 관리")
        .alert("태그 이름 바꾸기", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("태그", text: $newName).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("바꾸기") { if let old = renaming { store.renameTag(old, to: newName) } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("#\(renaming ?? "") 을(를) 쓰는 모든 항목이 바뀌어요")
        }
    }
}
