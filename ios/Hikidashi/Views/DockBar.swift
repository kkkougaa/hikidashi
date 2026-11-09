import SwiftUI
import HikidashiCore

/// 하단바의 칸: 홈 · 즐겨찾기 · 메모 · 설정
enum DockTab: Hashable { case home, starred, memos, settings }

/// 하단바: 홈 · 즐겨찾기 · 메모 · 설정. + 버튼과 떨어진 리퀴드 글래스.
/// 아래로 스크롤하면 + 버튼 쪽으로 쫀득하게 빨려 들어가고, 위로 올리면 다시 나온다
struct DockBar: View {
    let selected: DockTab?
    var onPick: (DockTab) -> Void
    /// 투명도 0(불투명)~0.8, 설정에서 바꾼다
    @AppStorage("dockClear") private var dockClear = 0.4

    var body: some View {
        HStack(spacing: 2) {
            tab("홈", "house", .home)
            tab("즐겨찾기", "star", .starred)
            tab("메모", "note.text", .memos, filled: "note.text")
            tab("설정", "gearshape", .settings)
        }
        .padding(5)
        .frame(height: 60)
        .background { glass }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func tab(_ title: String, _ icon: String, _ t: DockTab, filled: String? = nil) -> some View {
        let on = selected == t
        return Button { onPick(t) } label: {
            // 글씨 없이 아이콘만 (읽어 주는 이름은 accessibilityLabel)
            Image(systemName: on ? (filled ?? "\(icon).fill") : icon).font(.system(size: 21, weight: .semibold))
            .foregroundStyle(on ? Color.brand : .secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .background(on ? Color.primary.opacity(0.07) : .clear, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var glass: some View {
        let shape = Capsule(style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(Color(.systemBackground).opacity(max(0, 0.85 - dockClear))).interactive(), in: shape)
        } else {
            fallback(shape)
        }
        #else
        fallback(shape)
        #endif
    }

    private func fallback(_ shape: Capsule) -> some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(Color(.systemBackground).opacity(max(0, 0.85 - dockClear))))
            .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
    }
}

/// 아래로 스크롤하면 하단바를 접고, 위로 올리거나 맨 위면 펼친다 (iOS 18 부터. 그 전엔 늘 펼쳐 둔다)
struct CollapseOnScroll: ViewModifier {
    @Environment(LibraryStore.self) private var store

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { old, new in
                let d = new - old
                guard abs(d) > 4 else { return }
                let c = d > 0 && new > 40
                if c != store.chromeCollapsed {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { store.chromeCollapsed = c }
                }
            }
        } else {
            content
        }
    }
}
