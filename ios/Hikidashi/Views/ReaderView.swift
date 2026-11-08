import SwiftUI
import HikidashiCore

/// 리더 모드: 광고·메뉴 없이 본문만. 글꼴·글자 크기·줄 간격, 문단 형광펜, 원본 열기.
/// 한 번 연 본문은 기기에 저장돼서 원본이 사라져도 읽을 수 있다
struct ReaderView: View {
    let item: Item
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readerFontSize") private var fontSize: Double = 18
    @AppStorage("readerFont") private var fontName = "sans"
    @AppStorage("readerSpacing") private var spacing: Double = 0.45
    @State private var article: ReaderArticle?
    @State private var failed = false
    @State private var original: WebPage?

    /// 형광펜은 바뀌면 바로 보이게 가게에서 다시 읽는다
    private var highlights: [String] { store.item(item.id)?.highlights ?? item.highlights }

    var body: some View {
        NavigationStack {
            Group {
                if let article {
                    content(article)
                } else if failed {
                    ContentUnavailableView {
                        Label("본문을 가져오지 못했어요", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("로그인이 필요하거나 본문이 그림으로만 된 페이지일 수 있어요.")
                    } actions: {
                        Button("원본 열기") { openOriginal() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("본문 불러오는 중…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("리더 닫기")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Section("글꼴") {
                            Picker("글꼴", selection: $fontName) {
                                Text("고딕").tag("sans")
                                Text("명조").tag("serif")
                                Text("둥근").tag("rounded")
                            }
                        }
                        Section("글자 크기") {
                            Button { fontSize = min(28, fontSize + 2) } label: { Label("크게", systemImage: "textformat.size.larger") }
                            Button { fontSize = max(14, fontSize - 2) } label: { Label("작게", systemImage: "textformat.size.smaller") }
                        }
                        Section("줄 간격") {
                            Picker("줄 간격", selection: $spacing) {
                                Text("좁게").tag(0.25)
                                Text("보통").tag(0.45)
                                Text("넓게").tag(0.7)
                            }
                        }
                        Button { fontSize = 18; fontName = "sans"; spacing = 0.45 } label: { Label("기본으로", systemImage: "arrow.counterclockwise") }
                    } label: { Image(systemName: "textformat.size") }
                    .accessibilityLabel("글자 설정")
                    if let s = item.url, let url = URL(string: s) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("공유")
                    }
                    Button { openOriginal() } label: { Image(systemName: "safari") }.accessibilityLabel("원본 열기")
                }
            }
        }
        .task {
            let a = await store.article(for: item)
            withAnimation(.easeOut(duration: 0.2)) {
                article = a
                failed = a == nil
            }
        }
        .fullScreenCover(item: $original) { SafariView(url: $0.url).ignoresSafeArea() }
    }

    private func openOriginal() {
        if let s = item.url, let url = URL(string: s) { original = WebPage(url: url) }
    }

    private var design: Font.Design {
        switch fontName {
        case "serif": .serif
        case "rounded": .rounded
        default: .default
        }
    }

    private func font(_ scale: Double = 1, weight: Font.Weight = .regular) -> Font {
        .system(size: fontSize * scale, weight: weight, design: design)
    }

    private func content(_ a: ReaderArticle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: fontSize * 0.9) {
                VStack(alignment: .leading, spacing: 10) {
                    if let url = item.url { SourceChip(url: url, siteName: item.siteName ?? a.siteName) }
                    Text(item.title.isEmpty ? (a.title ?? item.displayTitle) : item.title)
                        .font(font(1.45, weight: .bold))
                        .lineSpacing(2)
                    HStack(spacing: 6) {
                        Text("약 \(a.minutes)분")
                        if a.savedAt != nil { Label("기기에 저장됨", systemImage: "arrow.down.circle.fill").labelStyle(.titleAndIcon) }
                        if !highlights.isEmpty { Label("\(highlights.count)", systemImage: "highlighter") }
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    if item.brokenAt != nil {
                        Label("원본 페이지가 열리지 않아요. 저장해 둔 본문이에요", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                if let hero = a.image ?? item.coverImage {
                    RemoteImage(url: hero).clipShape(.rect(cornerRadius: 14))
                }
                ForEach(Array(a.blocks.enumerated()), id: \.offset) { _, block in
                    marked(block)
                }
                Button { openOriginal() } label: {
                    Label("원본 페이지에서 보기", systemImage: "safari").frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 14))
                .padding(.top, 8)
                Text("문단을 길게 누르면 형광펜을 칠 수 있어요")
                    .font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 700, alignment: .leading)
        }
    }

    /// 형광펜 칠한 문단은 노란 바탕. 길게 누르면 칠하기·지우기·복사
    @ViewBuilder private func marked(_ block: ReaderBlock) -> some View {
        if let text = ReaderArticle.text(of: block) {
            let on = highlights.contains(text)
            view(block)
                .padding(.horizontal, on ? 6 : 0).padding(.vertical, on ? 3 : 0)
                .background(on ? Color.yellow.opacity(0.32) : .clear, in: .rect(cornerRadius: 6))
                .padding(.horizontal, on ? -6 : 0)
                .contentShape(.rect)
                .contextMenu {
                    Button { withAnimation(.snappy) { store.toggleHighlight(item, text: text) } } label: {
                        Label(on ? "형광펜 지우기" : "형광펜 칠하기", systemImage: on ? "eraser" : "highlighter")
                    }
                    Button { UIPasteboard.general.string = text } label: { Label("복사", systemImage: "doc.on.doc") }
                    ShareLink(item: text) { Label("공유", systemImage: "square.and.arrow.up") }
                }
        } else {
            view(block)
        }
    }

    @ViewBuilder private func view(_ block: ReaderBlock) -> some View {
        switch block {
        case .heading(let t, let level):
            Text(t).font(font(level <= 2 ? 1.25 : 1.1, weight: .bold)).padding(.top, fontSize * 0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let t):
            Text(t).font(font()).lineSpacing(fontSize * spacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .quote(let t):
            Text(t).font(font().italic()).lineSpacing(fontSize * spacing).foregroundStyle(.secondary)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Color.brand.opacity(0.5)).frame(width: 3) }
                .frame(maxWidth: .infinity, alignment: .leading)
        case .listItem(let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(font()).foregroundStyle(.secondary)
                Text(t).font(font()).lineSpacing(fontSize * spacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .code(let t):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(t).font(.system(size: fontSize * 0.8, design: .monospaced)).padding(12)
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
        case .image(let src):
            ReaderImage(url: src)
        }
    }
}

/// 못 불러온 그림은 자리를 비우지 않고 접는다
private struct ReaderImage: View {
    let url: String
    @State private var failed = false
    var body: some View {
        if !failed {
            RemoteImage(url: url, onFail: { failed = true }).clipShape(.rect(cornerRadius: 12))
        }
    }
}

/// 하이라이트 모아 보기: 항목별로 칠한 문단
struct HighlightsList: View {
    let items: [Item]
    @Environment(LibraryStore.self) private var store

    var body: some View {
        List {
            ForEach(items) { item in
                Section {
                    ForEach(item.highlights, id: \.self) { h in
                        Button { store.reader = ReaderRequest(item: item) } label: {
                            Text(h).font(.body).lineSpacing(4).foregroundStyle(.primary)
                                .padding(.leading, 12)
                                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Color.yellow).frame(width: 4) }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) { store.toggleHighlight(item, text: h) } label: { Label("지우기", systemImage: "eraser") }
                        }
                        .contextMenu {
                            Button { UIPasteboard.general.string = h } label: { Label("복사", systemImage: "doc.on.doc") }
                            ShareLink(item: "\(h)\n\n— \(item.displayTitle) \(item.url ?? "")") { Label("공유", systemImage: "square.and.arrow.up") }
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        ItemIcon(item: item, folder: store.folder(item.folderId), size: 22)
                        Text(item.displayTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    }
                    .textCase(nil)
                }
            }
            Color.clear.frame(height: 72).listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
    }
}
