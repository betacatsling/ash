import AppKit
import SwiftUI

struct GitReviewView: View {
    let context: PanelContext
    @State private var snapshot: ReviewSnapshot?
    @State private var selectedPath: String?
    @State private var error: String?
    @State private var refresh = UUID()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(
                    snapshot?.branch.isEmpty == false ? snapshot!.branch : "Git Diff",
                    systemImage: "arrow.triangle.branch"
                ).lineLimit(1)
                Spacer()
                Text("\(snapshot?.files.count ?? 0) 个文件").foregroundStyle(.secondary)
                Button {
                    refresh = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("刷新 Git 差异").accessibilityLabel("刷新 Git 差异")
            }.buttonStyle(.plain).font(.system(size: 11)).padding(12)
            Text(context.base.map { "基准 · \($0.prefix(8))" } ?? "基准 · HEAD")
                .help("包含暂存、未暂存及新文件")
                .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 8)
            Divider()
            if let snapshot {
                if snapshot.files.isEmpty {
                    PanelPlaceholder(title: "工作区是干净的", symbol: "checkmark.circle", detail: "文件发生变更后，可以在这里逐一查看差异。")
                } else {
                    VSplitView {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(snapshot.files) { file in
                                    Button {
                                        selectedPath = file.path
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(file.status).font(
                                                .system(size: 11, weight: .medium, design: .monospaced)
                                            )
                                            .foregroundStyle(
                                                file.status == "D" ? .red : file.status == "M" ? .orange : .green
                                            ).frame(width: 20)
                                            Text(file.path).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                                            Spacer(minLength: 0)
                                        }.padding(.horizontal, 12).frame(height: 28)
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).ashHover(selected: selectedPath == file.path).help(file.path)
                                }
                            }
                        }.frame(
                            minHeight: 60, idealHeight: 140,
                            maxHeight: max(60, min(280, CGFloat(snapshot.files.count * 28 + 16))))
                        if let selectedPath {
                            GitFileDiffView(context: context, path: selectedPath).id("\(selectedPath):\(refresh)")
                                .frame(minHeight: 120)
                        }
                    }
                }
            } else if let error {
                PanelPlaceholder(title: "无法读取 Git 差异", symbol: "arrow.triangle.branch", detail: error)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.task(id: refresh) {
            error = nil
            do {
                let result: ReviewSnapshot = try await context.call("reviewFiles")
                guard !Task.isCancelled else { return }
                snapshot = result
                if !result.files.contains(where: { $0.path == selectedPath }) {
                    selectedPath = result.files.first?.path
                }
            } catch {
                if !Task.isCancelled {
                    snapshot = nil
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

struct GitFileDiffView: View {
    let context: PanelContext
    let path: String
    @State private var result: ReviewDiff?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            Text(path).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            if let result {
                PanelCodeView(text: result.text.isEmpty ? "此文件当前没有差异。" : result.text, diff: true)
                if result.truncated { Text("仅预览前 512 KB").font(.caption2).foregroundStyle(.orange).padding(8) }
            } else if let error {
                PanelPlaceholder(title: "无法读取差异", symbol: "exclamationmark.triangle", detail: error)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.task {
            do {
                let value: ReviewDiff = try await context.call("reviewDiff", path: path)
                if !Task.isCancelled { result = value }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
