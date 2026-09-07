import SwiftUI

struct TerminalTabItem: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var drag: TerminalDragState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tab: TerminalTabGroup
    @State private var mergeGlow = false

    private var selected: Bool { store.selectedTerminalTab?.id == tab.id }
    private var isSource: Bool { drag.source?.tabID == tab.id }
    private var isTarget: Bool { drag.hoveredTabID == tab.id }
    private var members: [Run] { store.runs(in: tab) }

    var body: some View {
        HStack(spacing: 0) {
            tabContent
            Button {
                Task { await store.closeTerminalTab(tab) }
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .regular)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .opacity(selected ? 1 : 0).allowsHitTesting(selected).accessibilityHidden(!selected)
                .disabled(tab.runIDs.contains { store.closingRunIDs.contains($0) })
                .help(tab.isSplit ? "关闭此标签页中的所有终端，保留文件与记录" : "关闭终端，保留文件与记录")
                .accessibilityLabel("关闭标签页：\(store.title(for: tab))")
        }
        .padding(.trailing, 5).frame(height: AshStyle.toolbarHeight)
        .foregroundStyle(selected ? Color.primary : .secondary)
        .ashTab(selected: selected)
        .overlay {
            RoundedRectangle(cornerRadius: AshStyle.radius)
                .fill(ashAccent.opacity(mergeGlow ? 0.22 : isTarget ? 0.13 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: AshStyle.radius)
                        .strokeBorder(ashAccent.opacity(isTarget || mergeGlow ? 0.8 : 0), lineWidth: 1.5)
                }.allowsHitTesting(false)
        }
        .opacity(isSource ? 0.35 : 1)
        .scaleEffect(isSource && !reduceMotion ? 0.96 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSource)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isTarget)
        .background(TerminalTabDropTarget(id: tab.id, drag: drag))
        .contextMenu {
            if tab.isSplit {
                Button("左右排列") { store.arrangeTerminalTab(tab, axis: .horizontal) }
                Button("上下排列") { store.arrangeTerminalTab(tab, axis: .vertical) }
                Button("拆为独立标签页") { store.ungroupTerminalTab(tab) }
                Divider()
                ForEach(Array(members.enumerated()), id: \.element.id) { index, run in
                    Menu("\(index + 1) · \(store.terminalTitle(run, hostID: store.selectedHost.id))") {
                        Button("聚焦终端") { store.selectRun(run) }
                        Button("重命名…") { store.beginRenamingTerminal(run) }
                        Button("移到独立标签页") { store.detachTerminal(run.id) }
                        Button("关闭此终端") { Task { await store.closeTerminal(run) } }
                    }
                }
            } else if let run = members.first {
                Button("重命名…") { store.beginRenamingTerminal(run) }
                Button("查找终端内容") {
                    store.selectTerminalTab(tab)
                    DispatchQueue.main.async { store.terminalSearchRequest = UUID() }
                }
            }
            Divider()
            Button("关闭标签页") { Task { await store.closeTerminalTab(tab) } }
                .disabled(tab.runIDs.contains { store.closingRunIDs.contains($0) })
        }
        .task(id: drag.lastDrop?.id) {
            guard drag.lastDrop?.tabID == tab.id else {
                mergeGlow = false
                return
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { mergeGlow = true }
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { mergeGlow = false }
        }
    }

    @ViewBuilder private var tabContent: some View {
        if tab.isSplit {
            Button {
                store.selectTerminalTab(tab)
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 12))
                    .scaleEffect(mergeGlow && !reduceMotion ? 1.18 : 1)
                    .frame(width: 30, height: AshStyle.toolbarHeight)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .modifier(TerminalDragModifier(tab: tab))
                .accessibilityLabel("分屏标签：\(store.title(for: tab))，\(tab.runIDs.count) 个终端")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help("拖动图标移动整组；拖动终端名称可单独移出")
            ForEach(Array(members.enumerated()), id: \.element.id) { index, run in
                if index > 0 {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1, height: 10)
                        .accessibilityHidden(true)
                }
                memberButton(run, index: index)
            }
            Text("\(tab.runIDs.count)").font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(ashAccent.opacity(0.12), in: Capsule())
                .padding(.horizontal, 5)
        } else {
            Button {
                store.selectTerminalTab(tab)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: members.first?.symbol ?? "terminal").font(.system(size: 12))
                    Text(store.title(for: tab)).font(.system(size: 12, weight: .light))
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: 200)
                        .contentTransition(.opacity)
                    Circle().fill(members.contains(where: \.active) ? AshStyle.success : Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                }
                .padding(.leading, 15).padding(.trailing, 7).frame(height: AshStyle.toolbarHeight)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(store.title(for: tab))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .modifier(TerminalDragModifier(tab: tab))
                .help("\(store.title(for: tab))\n拖到另一个标签合并；拖到终端边缘选择分屏方向")
        }
    }

    private func memberButton(_ run: Run, index: Int) -> some View {
        let focused = selected && store.selectedRun?.id == run.id
        let dragging = drag.source?.tabID == nil && drag.source?.runID == run.id
        return Button {
            store.selectRun(run)
        } label: {
            Text(store.terminalTitle(run, hostID: store.selectedHost.id))
                .font(.system(size: 12, weight: .light)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 110).padding(.horizontal, 7).frame(height: 24)
                .background(focused ? ashAccent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .frame(height: AshStyle.toolbarHeight).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .opacity(dragging ? 0.3 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: dragging)
            .modifier(TerminalDragModifier(tab: tab, member: run))
            .accessibilityLabel("组内终端 \(index + 1)：\(store.terminalTitle(run, hostID: store.selectedHost.id))")
            .accessibilityAddTraits(focused ? .isSelected : [])
            .help("\(store.terminalTitle(run, hostID: store.selectedHost.id))\n拖到标签栏空白处成为独立标签；拖到其他终端旁边可重新分组")
    }

}
