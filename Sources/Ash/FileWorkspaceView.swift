import AppKit
import SwiftUI

struct FileWorkspaceView: View {
    let context: PanelContext
    @ObservedObject var tree: FileTreeModel
    let path: String?
    let open: (String) -> Void
    @State private var showTree = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(path ?? "/").font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button {
                    showTree.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }.help("显示或隐藏文件树").accessibilityLabel("显示或隐藏文件树")
            }.buttonStyle(AshIconButtonStyle()).foregroundStyle(.secondary).padding(.horizontal, 12)
                .frame(height: AshStyle.toolbarHeight).background(AshStyle.chrome)
            Divider()
            HStack(spacing: 0) {
                Group {
                    if let path {
                        FilePreviewView(context: context, path: path).id(path)
                    } else {
                        PanelPlaceholder(title: "选择文件", symbol: "doc.on.doc", detail: "从右侧目录树打开文件以预览内容。")
                    }
                }.frame(minWidth: 160, maxWidth: .infinity, maxHeight: .infinity)
                if showTree {
                    Divider()
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                            TextField("筛选文件…", text: $tree.filter).textFieldStyle(.plain).help("筛选已展开目录中的文件")
                            Button {
                                Task { await tree.refresh(context: context) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain).help("刷新目录").accessibilityLabel("刷新目录")
                        }.font(.system(size: 11)).padding(8).ashField().padding(8)
                        ScrollView([.vertical, .horizontal]) {
                            VStack(alignment: .leading, spacing: 0) {
                                FileTreeBranch(
                                    tree: tree, context: context, directory: "", depth: 0, selectedPath: path,
                                    open: open)
                            }.frame(minWidth: 160, alignment: .leading).padding(.bottom, 12)
                        }.defaultScrollAnchor(.topLeading)
                    }.frame(width: 184).frame(maxHeight: .infinity).background(AshStyle.chrome)
                }
            }
        }.task { if tree.children[""] == nil { await tree.load(context: context) } }
    }
}

struct FileTreeBranch: View {
    @ObservedObject var tree: FileTreeModel
    let context: PanelContext
    let directory: String
    let depth: Int
    let selectedPath: String?
    let open: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tree.visible(directory)) { entry in
                Button {
                    if entry.directory { Task { await tree.toggle(entry, context: context) } } else { open(entry.path) }
                } label: {
                    HStack(spacing: 6) {
                        Image(
                            systemName: entry.directory
                                ? (tree.expanded.contains(entry.path) ? "chevron.down" : "chevron.right")
                                : FileEntry.symbol(for: entry.path)
                        )
                        .font(.system(size: 11)).foregroundStyle(Color.secondary).frame(
                            width: 14)
                        Text(entry.name).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 8)
                    }.padding(.leading, CGFloat(depth * 12 + 8)).frame(height: 28)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).ashHover(selected: selectedPath == entry.path).help(entry.path)
                if entry.directory, tree.expanded.contains(entry.path), depth < 40 {
                    FileTreeBranch(
                        tree: tree, context: context, directory: entry.path, depth: depth + 1,
                        selectedPath: selectedPath, open: open)
                }
            }
            if tree.loading.contains(directory) { ProgressView().controlSize(.small).padding(12) }
            if let error = tree.errors[directory] {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("重试") { Task { await tree.load(directory, context: context) } }
                }.frame(maxWidth: 220).padding(12)
            } else if tree.children[directory]?.isEmpty == true {
                Text("空文件夹").font(.caption).foregroundStyle(.tertiary).padding(12)
            }
            if tree.truncated.contains(directory) {
                Text("仅显示前 5,000 项").font(.caption2).foregroundStyle(.orange).padding(8)
            }
        }
    }
}

struct FilePreviewView: View {
    let context: PanelContext
    let path: String
    @State private var preview: FilePreview?
    @State private var error: String?
    @State private var refresh = UUID()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(
                    preview.map { ByteCountFormatter.string(fromByteCount: Int64($0.size), countStyle: .file) }
                        ?? "文件预览")
                Spacer()
                Text("只读")
                Button {
                    refresh = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("重新读取文件").accessibilityLabel("重新读取文件")
                if context.host.isLocal {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: context.cwd).appendingPathComponent(path))
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }.help("在默认应用中打开").accessibilityLabel("在默认应用中打开")
                }
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary).padding(8)
            if let preview {
                if preview.binary {
                    PanelPlaceholder(title: "无法预览", symbol: "doc", detail: "二进制或非 UTF-8 文件")
                } else if preview.text.isEmpty {
                    PanelPlaceholder(title: "空文件", symbol: "doc")
                } else {
                    PanelCodeView(text: preview.text, diff: false)
                }
                if preview.truncated { Text("仅预览前 512 KB").font(.caption2).foregroundStyle(.orange).padding(8) }
            } else if let error {
                PanelPlaceholder(title: "无法读取文件", symbol: "doc.badge.ellipsis", detail: error)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.task(id: refresh) {
            preview = nil
            error = nil
            do {
                let result: FilePreview = try await context.call("readFile", path: path)
                guard !Task.isCancelled else { return }
                preview = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
