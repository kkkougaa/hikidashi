import PhotosUI
import SwiftUI
import HikidashiCore

// MARK: 메모 본문 칸 (서식)

/// 메모 본문 칸. 목록 줄에서 엔터를 치면 기호가 이어지고, 키보드 위 버튼으로 굵게·목록을 넣는다
struct MemoNoteField: View {
    @Binding var text: String
    var focus: FocusState<ItemEditor.Field?>.Binding

    var body: some View {
        if #available(iOS 18.0, *) {
            MemoNoteField18(text: $text, focus: focus)
        } else {
            // iOS 17: 커서 위치를 몰라서 엔터 이어 쓰기만 (끝에서 칠 때)
            TextField("메모", text: $text, axis: .vertical)
                .font(.body)
                .lineLimit(5...20)
                .focused(focus, equals: .note)
                .onChange(of: text) { old, new in
                    if let r = RichText.continueList(old: old, new: new) { text = r.text }
                }
        }
    }
}

@available(iOS 18.0, *)
private struct MemoNoteField18: View {
    @Binding var text: String
    var focus: FocusState<ItemEditor.Field?>.Binding
    @State private var selection: TextSelection?

    var body: some View {
        TextField("메모", text: $text, selection: $selection, axis: .vertical)
            .font(.body)
            .lineLimit(5...20)
            .focused(focus, equals: .note)
            .onChange(of: text) { old, new in
                guard let r = RichText.continueList(old: old, new: new) else { return }
                apply(r)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focus.wrappedValue == .note {
                        Button { edit { RichText.toggleBold($0, start: $1, end: $2) } } label: { Image(systemName: "bold") }
                            .accessibilityLabel("굵게")
                        Button { edit { RichText.toggleList($0, start: $1, end: $2, kind: .bullet) } } label: { Image(systemName: "list.bullet") }
                            .accessibilityLabel("글머리 기호 목록")
                        Button { edit { RichText.toggleList($0, start: $1, end: $2, kind: .number) } } label: { Image(systemName: "list.number") }
                            .accessibilityLabel("번호 목록")
                        Spacer()
                    }
                }
            }
    }

    /// 지금 고른 범위 (글자 단위). 모르면 글 끝
    private var range: (Int, Int) {
        let end = text.count
        guard let sel = selection, case .selection(let r) = sel.indices,
              r.lowerBound >= text.startIndex, r.upperBound <= text.endIndex else { return (end, end) }
        return (text.distance(from: text.startIndex, to: r.lowerBound), text.distance(from: text.startIndex, to: r.upperBound))
    }

    private func edit(_ f: (String, Int, Int) -> RichEdit) {
        let (s, e) = range
        apply(f(text, s, e))
    }

    private func apply(_ r: RichEdit) {
        text = r.text
        let a = text.index(text.startIndex, offsetBy: min(r.start, text.count))
        let b = text.index(text.startIndex, offsetBy: min(r.end, text.count))
        selection = TextSelection(range: a..<b)
    }
}

// MARK: 사진 아이콘 (자르기)

/// 아이콘을 사진에서 고르는 줄: 고르면 자르기 화면이 뜬다
struct IconPhotoRow: View {
    @Binding var icon: String?
    @State private var pick: PhotosPickerItem?
    @State private var cropping: CropSource?

    struct CropSource: Identifiable { let id = UUID(); let image: UIImage }

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pick, matching: .images) {
                HStack(spacing: 8) {
                    if let img = IconImage.image(icon) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 24, height: 24).clipShape(.rect(cornerRadius: 6))
                        Text("사진 바꾸기")
                    } else {
                        Image(systemName: "photo.badge.plus")
                        Text("사진에서 고르기")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            if icon != nil {
                Button("사진 빼기") { withAnimation(.snappy) { icon = nil } }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    cropping = CropSource(image: img)
                }
                pick = nil
            }
        }
        .fullScreenCover(item: $cropping) { src in
            IconCropView(image: src.image) { url in
                icon = url
                cropping = nil
            } onCancel: { cropping = nil }
        }
    }
}

/// 정사각형으로 잘라 아이콘 만들기: 끌어서 옮기고 두 손가락으로 키운다
struct IconCropView: View {
    let image: UIImage
    var onDone: (String) -> Void
    var onCancel: () -> Void

    /// 잘라 낸 아이콘 크기 (px). 동기화 파일에 그대로 들어가서 작게 둔다 (웹과 같음)
    static let output: CGFloat = 192
    private let frameSize: CGFloat = 300

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var startZoom: CGFloat = 1
    @State private var startOffset: CGSize = .zero

    private var base: CGFloat { frameSize / max(1, min(image.size.width, image.size.height)) }
    private var shown: CGSize { CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom) }

    private func clamp(_ o: CGSize, zoom z: CGFloat) -> CGSize {
        let w = image.size.width * base * z, h = image.size.height * base * z
        let mx = max(0, (w - frameSize) / 2), my = max(0, (h - frameSize) / 2)
        return CGSize(width: min(mx, max(-mx, o.width)), height: min(my, max(-my, o.height)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(uiImage: image)
                    .resizable()
                    .frame(width: shown.width, height: shown.height)
                    .offset(offset)
                    .frame(width: frameSize, height: frameSize)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 2))
                    .contentShape(.rect)
                    .gesture(
                        DragGesture()
                            .onChanged { v in offset = clamp(CGSize(width: startOffset.width + v.translation.width, height: startOffset.height + v.translation.height), zoom: zoom) }
                            .onEnded { _ in startOffset = offset }
                            .simultaneously(with: MagnifyGesture()
                                .onChanged { v in
                                    zoom = min(6, max(1, startZoom * v.magnification))
                                    offset = clamp(offset, zoom: zoom)
                                }
                                .onEnded { _ in startZoom = zoom; startOffset = offset })
                    )
                    .accessibilityLabel("자를 부분")
                HStack(spacing: 12) {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { zoom }, set: { zoom = $0; startZoom = $0; offset = clamp(offset, zoom: $0); startOffset = offset }), in: 1...6)
                        .accessibilityLabel("확대")
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                .frame(width: frameSize)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("아이콘 자르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onCancel() } label: { Image(systemName: "xmark") }.accessibilityLabel("취소")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { if let u = render() { onDone(u) } } label: { Image(systemName: "checkmark") }.accessibilityLabel("이 부분으로 쓰기")
                }
            }
        }
    }

    /// 틀 안에 보이는 부분을 작은 JPEG data URL 로
    private func render() -> String? {
        let o = Self.output
        let k = o / frameSize
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let out = UIGraphicsImageRenderer(size: CGSize(width: o, height: o), format: fmt).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: o, height: o))
            let rect = CGRect(x: ((frameSize - shown.width) / 2 + offset.width) * k,
                              y: ((frameSize - shown.height) / 2 + offset.height) * k,
                              width: shown.width * k, height: shown.height * k)
            image.draw(in: rect)
        }
        guard let data = out.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}
