import SafariServices
import SwiftUI
import HikidashiCore

/// + 버튼. 누르면 새 항목, 위로 끌면 같은 두께로 길어지고(리퀴드 글래스), 기준을 넘겨 놓으면 클립보드 링크를 바로 넣는다
struct PullAddButton: View {
    var onTap: () -> Void
    var onPull: () -> Void

    @State private var pull: CGFloat = 0
    @State private var armed = false
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 64
    private let arm: CGFloat = 84
    /// 끌수록 무거워지는 고무줄
    private func rubber(_ raw: CGFloat) -> CGFloat { 150 * (1 - exp(-raw / 150)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            if dragging {
                Text(armed ? "놓으면 복사한 링크 추가" : "위로 끌어 올리면 바로 추가")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(armed ? .white : Color(.systemBackground))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(armed ? Color.brand : Color.primary, in: .rect(cornerRadius: 12))
                    .fixedSize()
                    .offset(x: -40, y: -(size + pull + 12))
                    .transition(.opacity)
            }
            glass
                .frame(width: size, height: size + (reduceMotion ? 0 : pull))
                .overlay(alignment: .top) {
                    Image(systemName: armed ? "doc.on.clipboard" : "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: size, height: size)
                }
        }
        .frame(width: size, height: size, alignment: .bottom)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let raw = max(0, -v.translation.height)
                    if !dragging, raw > 8 { withAnimation(.easeOut(duration: 0.15)) { dragging = true } }
                    guard dragging else { return }
                    pull = rubber(raw)
                    let nowArmed = pull >= arm
                    if nowArmed != armed { withAnimation(.snappy(duration: 0.2)) { armed = nowArmed } }
                }
                .onEnded { v in
                    let moved = hypot(v.translation.width, v.translation.height)
                    if !dragging, moved < 10 { onTap() } else if armed { onPull() }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { pull = 0; armed = false; dragging = false }
                }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, new in new }
        .accessibilityElement()
        .accessibilityLabel("추가")
        .accessibilityHint("누르면 새 항목, 위로 끌어 올렸다 놓으면 복사한 링크를 바로 추가해요")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .accessibilityAction(named: "복사한 링크 바로 추가") { onPull() }
    }

    @ViewBuilder private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // iOS 26 진짜 리퀴드 글래스
            Color.clear.glassEffect(.regular.tint(Color.brand).interactive(), in: shape)
        } else {
            fallbackGlass(shape)
        }
        #else
        fallbackGlass(shape)
        #endif
    }

    /// iOS 26 이전: 반투명 유리 흉내 (블러 + 위쪽 반사광 + 안쪽 그림자)
    private func fallbackGlass(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(Color.brand.opacity(0.82))
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .center)))
            .overlay(shape.strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .shadow(color: Color.brand.opacity(0.35), radius: 12, y: 8)
    }
}

/// 아래쪽 알림 (되돌리기 포함)
struct ToastView: View {
    let toast: ToastMessage
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(toast.text).font(.subheadline.weight(.medium)).lineLimit(2)
                .foregroundStyle(toast.isError ? Color(red: 1, green: 0.55, blue: 0.5) : .white)
            Spacer(minLength: 8)
            if let undo = toast.undo {
                Button("되돌리기") { undo(); onClose() }.font(.subheadline.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 8)
            }
            Button(action: onClose) { Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 32, height: 32) }
                .accessibilityLabel("알림 닫기")
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 8)
        .background(Color(white: 0.1), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
    }
}

/// 링크는 앱 안의 사파리로 연다
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Color.brand)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
