import UniformTypeIdentifiers
import SwiftUI
import HikidashiCore

/// 메모 보기: 큰 제목, "서랍 ··· 값" 줄들, 본문, 맨 아래 삭제
struct MemoDetail: View {
    let item: Item
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if let e = item.emoji { Text(e).font(.system(size: 30)) }
                        Text(item.title.isEmpty ? "제목 없는 메모" : item.title).font(.title.weight(.medium))
                    }
                    .padding(.bottom, 12)
                    row("서랍") {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(store.folder(item.folderId)?.color.color ?? unfiledColor).frame(width: 5, height: 18)
                            Text(store.folder(item.folderId)?.name ?? "미분류")
                        }
                    }
                    row("저장한 날") { Text(store.dates.stamp(item.createdAt)).monospacedDigit() }
                    if !item.tags.isEmpty {
                        row("태그") { Text(item.tags.map { "#\($0)" }.joined(separator: " ")).foregroundStyle(Color.brand) }
                    }
                    if item.starred { row("즐겨찾기") { Image(systemName: "star.fill").foregroundStyle(Color.star) } }
                    if !item.note.isEmpty {
                        Text(item.note).font(.body).lineSpacing(4).textSelection(.enabled).padding(.vertical, 16)
                    }
                    Button(role: .destructive) {
                        dismiss()
                        store.remove(item)
                    } label: {
                        Text("삭제").frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 16)).tint(.red)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("메모 닫기")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { dismiss(); store.editor = EditorRequest(editing: item) } label: { Image(systemName: "pencil") }.accessibilityLabel("편집")
                    Menu {
                        Button { store.toggleStar(item) } label: { Label(item.starred ? "즐겨찾기 해제" : "즐겨찾기", systemImage: "star") }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("더 보기")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(36)
    }

    private func row<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label)
            Spacer()
            value().foregroundStyle(.secondary)
        }
        .frame(minHeight: 52)
    }
}

struct FolderEdit: Identifiable {
    let id = UUID()
    var folder: Folder?
}

/// 서랍 만들기·고치기: ‹ · 제목 · ✓, 이름, 색 17가지, 서랍 삭제
struct FolderEditor: View {
    let folder: Folder?
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: FolderColor = .blue
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("서랍 이름", text: $name).font(.title2.weight(.semibold)).onChange(of: name) { error = nil }
                    if let error { Text(error).font(.footnote.weight(.semibold)).foregroundStyle(.red) }
                    Text("색").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 10)], spacing: 10) {
                        ForEach(FolderColor.allCases, id: \.self) { c in
                            Button { color = c } label: {
                                RoundedRectangle(cornerRadius: 12).fill(c.color).aspectRatio(1, contentMode: .fit)
                                    .overlay { if color == c { Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(.white) } }
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color == c ? c.color : .clear, lineWidth: 2).padding(-4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(c.koreanName)
                            .accessibilityAddTraits(color == c ? .isSelected : [])
                        }
                    }
                    if let folder {
                        let n = store.library.count(inFolder: folder.id)
                        Button(role: .destructive) { dismiss(); store.removeFolder(folder) } label: {
                            Text("서랍 삭제").frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 16)).tint(.red)
                        if n > 0 { Text("안의 항목 \(n)개는 미분류로 옮겨져요").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                    }
                }
                .padding(20)
            }
            .navigationTitle(folder == nil ? "새 서랍" : "서랍 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("닫기") }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark") }.accessibilityLabel(folder == nil ? "서랍 만들기" : "변경 사항 저장")
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { name = folder?.name ?? ""; color = folder?.color ?? .blue }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { error = "서랍 이름을 적어주세요"; return }
        guard !store.folders.contains(where: { $0.name == n && $0.id != folder?.id }) else { error = "같은 이름의 서랍이 이미 있어요"; return }
        if let folder { store.updateFolder(folder.id, name: n, color: color) } else { store.addFolder(name: n, color: color) }
        dismiss()
    }
}

