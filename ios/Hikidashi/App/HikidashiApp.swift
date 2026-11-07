import SwiftUI
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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Color.brand)
        }
    }
}

enum Tab: Hashable { case all, starred, folders, settings }

struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @State private var tab: Tab = .all
    @State private var folderPath = NavigationPath()

    var body: some View {
        @Bindable var store = store
        TabView(selection: $tab) {
            NavigationStack { ItemsScreen(scope: .all) }
                .tabItem { Label("전체", systemImage: "tray") }.tag(Tab.all)
            NavigationStack { ItemsScreen(scope: .starred) }
                .tabItem { Label("즐겨찾기", systemImage: "star") }.tag(Tab.starred)
            NavigationStack(path: $folderPath) { FoldersScreen() }
                .tabItem { Label("서랍", systemImage: "archivebox") }.tag(Tab.folders)
            NavigationStack { SettingsScreen() }
                .tabItem { Label("설정", systemImage: "gearshape") }.tag(Tab.settings)
        }
        .overlay(alignment: .bottomTrailing) {
            if tab != .settings {
                PullAddButton(
                    onTap: { store.editor = EditorRequest() },
                    onPull: { store.quickAddFromPasteboard(folderId: currentFolderId) }
                )
                .padding(.trailing, 18)
                .padding(.bottom, 64)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let t = store.toast {
                ToastView(toast: t) { withAnimation(.snappy) { store.toast = nil } }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 140)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $store.editor) { req in
            ItemEditor(request: req, defaultFolderId: currentFolderId ?? store.folders.first?.id)
        }
        .sheet(isPresented: Binding(get: { store.memoID != nil && store.item(store.memoID) != nil }, set: { if !$0 { store.memoID = nil } })) {
            if let m = store.item(store.memoID) { MemoDetail(item: m) }
        }
        .fullScreenCover(item: $store.webPage) { SafariView(url: $0.url).ignoresSafeArea() }
        .onOpenURL { url in
            // hikidashi://add?url=… 로 들어오면 새 항목 시트를 연다 (단축어·공유 확장용)
            guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let s = c.queryItems?.first(where: { $0.name == "url" })?.value, let u = normalizeURL(s) ?? findURL(in: s) else { return }
            store.editor = EditorRequest(prefill: ItemDraft(kind: .link, url: u))
        }
    }

    /// 지금 보고 있는 서랍 (서랍 탭에서 서랍 안에 있을 때)
    private var currentFolderId: String? { nil }
}
