import SwiftUI

/// 아래 탭: 홈 · 즐겨찾기 · 메모 · 설정 (iOS 기본 탭 막대). add 는 화면이 아니라 + 버튼 칸
enum RootTab: Hashable { case home, starred, memos, settings, add }

/// 아래로 스크롤하면 iOS 탭 막대를 줄인다 (iOS 26 부터. 그 전엔 그대로)
struct MinimizeTabBarOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
