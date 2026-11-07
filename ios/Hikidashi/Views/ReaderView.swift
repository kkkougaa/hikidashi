import SwiftUI
import HikidashiCore

/// 리더 모드: 광고·메뉴 없이 본문만. 글자 크기 조절, 원본 열기
struct ReaderView: View {
    let item: Item
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readerFontSize") private var fontSize: Double = 18
    @State private var article: ReaderArticle?
    @State private var failed = false
    @State private var original: WebPage?

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
                        Button { fontSize = min(28, fontSize + 2) } label: { Label("글자 크게", systemImage: "textformat.size.larger") }
                        Button { fontSize = max(14, fontSize - 2) } label: { Label("글자 작게", systemImage: "textformat.size.smaller") }
                        Button { fontSize = 18 } label: { Label("기본 크기", systemImage: "arrow.counterclockwise") }
                    } label: { Image(systemName: "textformat.size") }
                    .accessibilityLabel("글자 크기")
                    if let s = item.url, let url = URL(string: s) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("공유")
                    }
                    Button { openOriginal() } label: { Image(systemName: "safari") }.accessibilityLabel("원본 열기")
                }
            }
        }
        .task {
            guard let url = item.url else { failed = true; return }
            let a = await store.article(for: url)
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

    private func content(_ a: ReaderArticle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: fontSize * 0.9) {
                VStack(alignment: .leading, spacing: 10) {
                    if let url = item.url { SourceChip(url: url, siteName: item.siteName ?? a.siteName) }
                    Text(a.title ?? item.displayTitle)
                        .font(.system(size: fontSize * 1.45, weight: .bold))
                        .lineSpacing(2)
                    Text("약 \(a.minutes)분 · \(store.dates.stamp(item.createdAt)) 저장")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let hero = a.image ?? item.coverImage {
                    RemoteImage(url: hero).clipShape(.rect(cornerRadius: 14))
                }
                ForEach(Array(a.blocks.enumerated()), id: \.offset) { _, block in
                    view(block)
                }
                Button { openOriginal() } label: {
                    Label("원본 페이지에서 보기", systemImage: "safari").frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 14))
                .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 700, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder private func view(_ block: ReaderBlock) -> some View {
        let body = Font.system(size: fontSize)
        switch block {
        case .heading(let t, let level):
            Text(t).font(.system(size: fontSize * (level <= 2 ? 1.25 : 1.1), weight: .bold)).padding(.top, fontSize * 0.4)
        case .paragraph(let t):
            Text(t).font(body).lineSpacing(fontSize * 0.45)
        case .quote(let t):
            Text(t).font(body.italic()).lineSpacing(fontSize * 0.4).foregroundStyle(.secondary)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Color.brand.opacity(0.5)).frame(width: 3) }
        case .listItem(let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(body).foregroundStyle(.secondary)
                Text(t).font(body).lineSpacing(fontSize * 0.4)
            }
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
