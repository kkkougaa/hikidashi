import SafariServices
import SwiftUI
import CoreHaptics
import HikidashiCore

/// + 버튼. 동그란 리퀴드 글래스. 누르면 새 항목, 위로 끌면 같은 두께의 캡슐로 늘어나고, 기준을 넘겨 놓으면 클립보드 링크를 바로 넣는다
struct PullAddButton: View {
    var onTap: () -> Void
    var onPull: () -> Void

    @State private var pull: CGFloat = 0
    @State private var armed = false
    @State private var dragging = false
    /// 손가락이 닿아 있는 동안: 젤리처럼 옆으로 퍼지며 10% 커진다
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 60
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
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: size, height: size)
                }
                // 짜부: 가로는 더, 세로는 덜 커져서 눌린 젤리처럼 (끌어올리는 중엔 길어지는 쪽이 우선)
                .scaleEffect(x: pressed && !reduceMotion ? 1.12 : 1, y: pressed && !reduceMotion ? (dragging ? 1 : 1.03) : 1, anchor: .bottom)
        }
        .frame(width: size, height: size, alignment: .bottom)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !pressed {
                        // 닿는 순간: 톡 + 눌림
                        Haptics.shared.touchDown()
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { pressed = true }
                    }
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
                    // 떼는 순간: 위이잉 (세졌다 잦아드는 진동) + 젤리처럼 출렁이며 돌아온다
                    Haptics.shared.release(strong: armed)
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.38)) { pressed = false }
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
        let shape = Capsule(style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // iOS 26 진짜 리퀴드 글래스. 강조색을 옅게 물들여 뒤가 비친다
            Color.clear
                .glassEffect(.regular.tint(Color.brand.opacity(armed ? 0.85 : 0.6)).interactive(), in: shape)
                .shadow(color: Color.brand.opacity(0.25), radius: 14, y: 8)
        } else {
            fallbackGlass(shape)
        }
        #else
        fallbackGlass(shape)
        #endif
    }

    /// iOS 26 이전: 반투명 유리 흉내 (블러 + 위쪽 반사광 + 안쪽 그림자)
    private func fallbackGlass(_ shape: Capsule) -> some View {
        shape
            .fill(Color.brand.opacity(0.72))
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .center)))
            .overlay(shape.strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .shadow(color: Color.brand.opacity(0.35), radius: 12, y: 8)
    }
}

/// 위쪽에 잠깐 뜨는 작은 알림 (되돌리기 포함). 위로 밀거나 누르면 닫힌다
struct ToastView: View {
    let toast: ToastMessage
    var onClose: () -> Void
    @State private var drag: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : (toast.undo != nil ? "checkmark.circle.fill" : "info.circle.fill"))
                .foregroundStyle(toast.isError ? Color.red : Color.brand)
            Text(toast.text).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
            if let undo = toast.undo {
                Button("되돌리기") { undo(); onClose() }
                    .font(.subheadline.weight(.bold)).foregroundStyle(Color.brand)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 44)
        .modifier(GlassCapsule())
        .offset(y: min(0, drag))
        .gesture(DragGesture().onChanged { drag = $0.translation.height }.onEnded { v in
            if v.translation.height < -12 { onClose() } else { withAnimation(.snappy) { drag = 0 } }
        })
        .onTapGesture { if toast.undo == nil { onClose() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// 리퀴드 글래스 캡슐 (iOS 26 전에는 반투명 재질)
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
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

/// 추가 버튼 진동. 닿을 때 짧게 톡, 뗄 때 위이잉(세졌다가 잦아드는 쫀득한 진동)
@MainActor
final class Haptics {
    static let shared = Haptics()
    private var engine: CHHapticEngine?
    private let tap = UIImpactFeedbackGenerator(style: .soft)

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
    }

    func touchDown() {
        tap.prepare()
        tap.impactOccurred(intensity: 0.7)
    }

    func release(strong: Bool = false) {
        guard let engine else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }
        // 0.26초 동안 세기가 0.35 → 1 → 0 으로, 끝에 작은 톡
        let peak: Float = strong ? 1 : 0.85
        let hum = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: peak),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.18),
        ], relativeTime: 0, duration: 0.26)
        let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.35),
            .init(relativeTime: 0.08, value: 1),
            .init(relativeTime: 0.26, value: 0),
        ], relativeTime: 0)
        let tick = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
        ], relativeTime: 0.27)
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: [hum, tick], parameterCurves: [curve])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }
}
