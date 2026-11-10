import SwiftUI
import BackgroundTasks
import HikidashiCore

@main
struct HikidashiApp: App {
    /// 화면 테스트는 "-uiTestSample" 로 띄워 예시 데이터를 쓴다 (실제 데이터는 건드리지 않음)
    @State private var store: LibraryStore = {
        if ProcessInfo.processInfo.arguments.contains("-uiTestSample") {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ui-test-library.json")
            return LibraryStore(fileURL: tmp, sample: true)
        }
        return LibraryStore()
    }()

    init() {
        // 앱이 닫혀 있어도 iOS 가 가끔 깨워 주면 드롭박스와 맞춰 둔다
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundSync.id, using: nil) { BackgroundSync.handle($0) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Color.brand)
        }
    }
}

/// 한 화면: 항목 목록 + 왼쪽에서 나오는 서랍 + 떠 있는 + 버튼
struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"
    @State private var scope: Scope = .all
    @State private var drawerOpen = false
    @State private var drag: CGFloat = 0
    /// 아래 탭 (iOS 기본 탭 막대, 리퀴드 글래스)
    @State private var tab: RootTab = .home
    @AppStorage("viewMode") private var viewMode = "rows"
    /// 설정: 탭 막대에 이름 없이 그림만
    @AppStorage("hideTabTitles") private var hideTabTitles = false

    /// 탭 그림과 이름. 이름을 숨겨도 읽어 주는 이름은 남긴다
    @ViewBuilder private func tabLabel(_ title: String, _ icon: String) -> some View {
        if hideTabTitles {
            Image(systemName: icon).accessibilityLabel(title)
        } else {
            Label(title, systemImage: icon)
        }
    }

    /// 서랍에서 고른 범위: 즐겨찾기·메모는 그 탭으로, 나머지는 홈 탭에서 본다
    private var drawerSelected: Scope {
        switch tab {
        case .starred: .starred
        case .memos: .memos
        default: scope
        }
    }

    private func pick(_ s: Scope) {
        store.stopSelecting()
        switch s {
        case .starred: tab = .starred
        case .memos: tab = .memos
        default: scope = s; tab = .home
        }
    }

    var body: some View {
        @Bindable var store = store
        GeometryReader { geo in
            let width = min(320, geo.size.width * 0.84)
            let progress = drawerProgress(width)
            ZStack(alignment: .leading) {
                tabs
                .modifier(MinimizeTabBarOnScroll())
                .onChange(of: tab) { old, new in
                    // + 칸은 화면이 아니라 버튼: 누르면 새 항목을 열고 보던 탭에 머문다
                    if new == .add {
                        tab = old
                        store.editor = EditorRequest()
                    } else {
                        store.stopSelecting()
                    }
                }
                .sensoryFeedback(.selection, trigger: tab)

                // 서랍이 열리면 뒤를 어둡게, 누르면 닫힘
                Color.black.opacity(0.32 * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(progress > 0.01)
                    .onTapGesture { setDrawer(false) }
                    .gesture(closeDrag(width))

                DrawerView(selected: drawerSelected, onSelect: { s in
                    pick(s)
                    setDrawer(false)
                }, onSettings: {
                    setDrawer(false)
                    tab = .settings
                }, onOpen: { it in
                    setDrawer(false)
                    store.open(it)
                })
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.18 * progress), radius: 20, x: 6)
                .offset(x: -width - 24 + (width + 24) * progress)
                .simultaneousGesture(closeDrag(width))
                .accessibilityHidden(!drawerOpen)

                // 왼쪽 가장자리에서 밀면 서랍이 따라 나온다
                if !drawerOpen, store.selection == nil {
                    Color.clear
                        .frame(width: 22)
                        .contentShape(.rect)
                        .ignoresSafeArea()
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { drag = max(0, $0.translation.width) }
                                .onEnded { v in
                                    let open = v.translation.width > width * 0.35 || v.predictedEndTranslation.width > width * 0.6
                                    withAnimation(.snappy(duration: 0.3)) { drawerOpen = open; drag = 0 }
                                }
                        )
                }
            }
        }
        .overlay(alignment: .top) {
            if let t = store.toast {
                ToastView(toast: t) { withAnimation(.snappy) { store.toast = nil } }
                    .padding(.horizontal, 24)
                    .padding(.top, 52) // 위쪽 버튼 줄은 가리지 않게
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(t.id)
            }
        }
        .sensoryFeedback(.selection, trigger: drawerOpen)
        .sheet(item: $store.editor) { req in
            ItemEditor(request: req, defaultFolderId: currentFolderId ?? store.defaultFolderId)
        }
        .sheet(isPresented: Binding(get: { store.memoID != nil && store.item(store.memoID) != nil }, set: { if !$0 { store.memoID = nil } })) {
            if let m = store.item(store.memoID) { MemoDetail(item: m) }
        }
        .sheet(item: $store.reader) { ReaderView(item: $0.item) }
        .sheet(item: $store.offlineView) { OfflineView(id: $0.id) }
        .fullScreenCover(item: $store.webPage) { SafariView(url: $0.url).ignoresSafeArea() }
        .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
        .onChange(of: scenePhase) { _, phase in if phase == .active {
                store.drainShareInbox()
                store.checkLinks()
                Task {
                    await store.syncNow()
                    store.startLiveSync()
                }
                Task.detached(priority: .background) { ImageCache.trim() }
            } else if phase == .background {
                store.stopLiveSync()
                BackgroundSync.schedule()
            } }
        .onAppear {
            // 타임라인 보기(list)는 없앴다: 리스트로
            if viewMode != "grid" { viewMode = "rows" }
        }
        .onChange(of: store.folders.map(\.id)) { _, ids in
            // 보고 있던 서랍이 지워지면 전체로
            if case .folder(let id) = scope, !ids.contains(id) { scope = .all }
        }
        .onOpenURL { url in
            // hikidashi://add?url=… 로 들어오면 새 항목 시트를 연다 (단축어용)
            guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let s = c.queryItems?.first(where: { $0.name == "url" })?.value, let u = normalizeURL(s) ?? findURL(in: s) else { return }
            store.editor = EditorRequest(prefill: ItemDraft(kind: .link, url: u))
        }
    }

    /// 아래 탭들. iOS 18 부터는 + 를 검색 역할 칸으로 둬서 탭 막대 오른쪽의 따로 떨어진 유리 동그라미가 된다.
    /// 아래로 스크롤하면 탭 막대가 줄어들며 + 쪽으로 모인다 (iOS 26 시스템 효과)
    @ViewBuilder private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $tab) {
                Tab(value: RootTab.home) { itemsTab(scope, fab: false).id(scope) } label: { tabLabel("홈", "house") }
                Tab(value: RootTab.starred) { itemsTab(.starred, fab: false) } label: { tabLabel("즐겨찾기", "star") }
                Tab(value: RootTab.memos) { itemsTab(.memos, fab: false) } label: { tabLabel("메모", "note.text") }
                Tab(value: RootTab.settings) { NavigationStack { SettingsScreen(embedded: true, onMenu: { setDrawer(true) }) } } label: { tabLabel("설정", "gearshape") }
                Tab(value: RootTab.add, role: .search) { Color.clear } label: { Label("추가", systemImage: "plus") }
            }
        } else {
            // iOS 17: 예전 탭 막대 + 떠 있는 + 버튼
            TabView(selection: $tab) {
                itemsTab(scope, fab: true).id(scope).tabItem { tabLabel("홈", "house") }.tag(RootTab.home)
                itemsTab(.starred, fab: true).tabItem { tabLabel("즐겨찾기", "star") }.tag(RootTab.starred)
                itemsTab(.memos, fab: true).tabItem { tabLabel("메모", "note.text") }.tag(RootTab.memos)
                NavigationStack { SettingsScreen(embedded: true, onMenu: { setDrawer(true) }) }
                    .tabItem { tabLabel("설정", "gearshape") }.tag(RootTab.settings)
            }
        }
    }

    /// 목록 탭 하나. 고르는 중엔 탭 막대를 숨긴다. fab 이면 오른쪽 아래에 떠 있는 + 버튼 (iOS 17)
    private func itemsTab(_ s: Scope, fab: Bool) -> some View {
        NavigationStack {
            ItemsScreen(scope: s, onMenu: { setDrawer(true) })
                .toolbar(store.selection != nil ? .hidden : .visible, for: .tabBar)
        }
        .overlay(alignment: .bottomTrailing) {
            if fab, store.selection == nil {
                PullAddButton(
                    onTap: { store.editor = EditorRequest() },
                    onPull: { store.quickAddFromPasteboard(into: currentFolderId) }
                )
                .padding(.trailing, 20)
                .padding(.bottom, 12)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    /// 지금 보고 있는 서랍
    private var currentFolderId: String? {
        if tab == .home, case .folder(let id) = scope { return id }
        return nil
    }

    private func drawerProgress(_ width: CGFloat) -> CGFloat {
        let p = drawerOpen ? 1 + min(0, drag) / width : max(0, drag) / width
        return min(1, max(0, p))
    }

    private func setDrawer(_ open: Bool) {
        withAnimation(.snappy(duration: 0.3)) { drawerOpen = open; drag = 0 }
    }

    private func closeDrag(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                // 세로 스크롤은 서랍 안 목록에 맡긴다
                guard drawerOpen, abs(v.translation.width) > abs(v.translation.height) else { return }
                drag = min(0, v.translation.width)
            }
            .onEnded { v in
                guard drawerOpen, drag < 0 || abs(v.translation.width) > abs(v.translation.height) else { drag = 0; return }
                let close = v.translation.width < -width * 0.3 || v.predictedEndTranslation.width < -width * 0.5
                withAnimation(.snappy(duration: 0.3)) { drawerOpen = !close; drag = 0 }
            }
    }
}

/// 백그라운드 새로 고침: iOS 가 정한 때(보통 몇십 분~몇 시간 간격)에 한 번 맞춘다
enum BackgroundSync {
    static let id = "com.kkkougaa.hikidashi.sync"

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    static func handle(_ task: BGTask) {
        schedule()
        let work = Task { @MainActor in
            await LibraryStore.current?.syncNow()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
