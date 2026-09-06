import SwiftUI

struct WorkspaceChecklistView: View {
    @ObservedObject var checklist: WorkspaceChecklistStore
    let hostID: String
    let workspaceID: String
    let workspaceName: String
    @State private var newTask = ""
    @State private var showCompleted = true
    private var tasks: [ChecklistTask] { checklist.tasks(hostID: hostID, workspaceID: workspaceID) }
    private var completed: [ChecklistTask] { tasks.filter(\.completed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("任务清单").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(workspaceName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text("\(completed.count) / \(tasks.count) 完成").font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !tasks.isEmpty {
                    ProgressView(value: Double(completed.count), total: Double(tasks.count)).tint(ashAccent)
                        .accessibilityLabel("任务完成进度")
                }
            }.padding(20)
            HStack(spacing: 10) {
                Image(systemName: "plus").foregroundStyle(ashAccent)
                TextField("添加任务", text: $newTask).textFieldStyle(.plain).font(.system(size: 12)).onSubmit(addTask)
                Button("添加", action: addTask).controlSize(.small)
                    .disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(12).ashField().padding(
                .horizontal, 12
            ).padding(.bottom, 12)
            if let error = checklist.error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    Button("重新加载") { checklist.reload() }.font(.caption)
                }.padding(12)
            }
            AshHairline()
            if tasks.isEmpty {
                PanelPlaceholder(title: "为工作区添一件待办", symbol: "checklist", detail: "在上方输入任务，按回车添加。")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tasks.filter { !$0.completed }) { task in row(task) }
                        if !completed.isEmpty {
                            DisclosureGroup(isExpanded: $showCompleted) {
                                ForEach(completed) { task in row(task) }
                            } label: {
                                Text("已完成 · \(completed.count)").font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }.padding(.top, 16).padding(.horizontal, 12)
                        }
                    }.padding(.vertical, 8)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func row(_ task: ChecklistTask) -> some View {
        ChecklistTaskRow(checklist: checklist, task: task, hostID: hostID, workspaceID: workspaceID)
    }
    private func addTask() {
        if checklist.add(newTask, hostID: hostID, workspaceID: workspaceID) { newTask = "" }
    }
}

private struct ChecklistTaskRow: View {
    @ObservedObject var checklist: WorkspaceChecklistStore
    let task: ChecklistTask
    let hostID: String
    let workspaceID: String
    @State private var expanded = true
    @State private var addingSubtask = false
    @State private var newSubtask = ""
    @State private var confirmDelete = false
    @FocusState private var subtaskFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9)).frame(
                        width: 16, height: 28)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .opacity(task.subtasks.isEmpty && !addingSubtask ? 0 : 1)
                    .disabled(task.subtasks.isEmpty && !addingSubtask).accessibilityLabel("展开或折叠 \(task.title) 的子任务")
                ChecklistCheckmark(title: task.title, completed: task.completed) {
                    checklist.toggle(task.id, hostID: hostID, workspaceID: workspaceID)
                }
                ChecklistTitleField(title: task.title, completed: task.completed) { title in
                    checklist.rename(task.id, title: title, hostID: hostID, workspaceID: workspaceID)
                }
                if !task.subtasks.isEmpty {
                    Text("\(task.completedSubtasks)/\(task.subtasks.count)").font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Menu {
                    Button("添加子任务", systemImage: "plus") {
                        expanded = true
                        addingSubtask = true
                        subtaskFocused = true
                    }
                    Divider()
                    Button("上移", systemImage: "arrow.up") {
                        checklist.move(task.id, offset: -1, hostID: hostID, workspaceID: workspaceID)
                    }
                    Button("下移", systemImage: "arrow.down") {
                        checklist.move(task.id, offset: 1, hostID: hostID, workspaceID: workspaceID)
                    }
                    Divider()
                    Button("删除任务…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("任务操作").accessibilityLabel(
                    "\(task.title) 的任务操作")
            }.padding(.horizontal, 12).padding(.vertical, 8).ashHover()
            if expanded {
                ForEach(task.subtasks) { subtask in
                    ChecklistSubtaskRow(
                        checklist: checklist, subtask: subtask, parent: task.id, hostID: hostID,
                        workspaceID: workspaceID
                    )
                    .padding(.leading, 40).padding(.trailing, 12)
                }
                if addingSubtask {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(ashAccent)
                        TextField("添加子任务", text: $newSubtask).textFieldStyle(.plain).font(.system(size: 12))
                            .focused($subtaskFocused).onSubmit(addSubtask).onExitCommand { addingSubtask = false }
                        Button("添加", action: addSubtask).controlSize(.small).disabled(
                            newSubtask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button {
                            addingSubtask = false
                            newSubtask = ""
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9))
                        }
                        .buttonStyle(.plain).accessibilityLabel("取消添加子任务")
                    }.padding(8).ashField()
                        .padding(.leading, 40).padding(.trailing, 12).padding(.vertical, 4)
                }
            }
            Divider().padding(.leading, 40).padding(.top, 4)
        }.confirmationDialog("删除“\(task.title)”？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除任务", role: .destructive) { checklist.delete(task.id, hostID: hostID, workspaceID: workspaceID) }
        } message: {
            Text(task.subtasks.isEmpty ? "该任务将从工作区清单中删除。" : "该任务及其 \(task.subtasks.count) 个子任务将一并删除。")
        }
    }
    private func addSubtask() {
        if checklist.add(newSubtask, parent: task.id, hostID: hostID, workspaceID: workspaceID) {
            newSubtask = ""
            subtaskFocused = true
        }
    }
}

private struct ChecklistSubtaskRow: View {
    @ObservedObject var checklist: WorkspaceChecklistStore
    let subtask: ChecklistSubtask
    let parent: UUID
    let hostID: String
    let workspaceID: String
    @State private var confirmDelete = false
    var body: some View {
        HStack(spacing: 8) {
            ChecklistCheckmark(title: subtask.title, completed: subtask.completed) {
                checklist.toggle(subtask.id, parent: parent, hostID: hostID, workspaceID: workspaceID)
            }
            ChecklistTitleField(title: subtask.title, completed: subtask.completed) { title in
                checklist.rename(subtask.id, title: title, parent: parent, hostID: hostID, workspaceID: workspaceID)
            }
            Menu {
                Button("上移", systemImage: "arrow.up") {
                    checklist.move(subtask.id, offset: -1, parent: parent, hostID: hostID, workspaceID: workspaceID)
                }
                Button("下移", systemImage: "arrow.down") {
                    checklist.move(subtask.id, offset: 1, parent: parent, hostID: hostID, workspaceID: workspaceID)
                }
                Divider()
                Button("删除子任务…", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(
                "\(subtask.title) 的子任务操作")
        }.padding(.vertical, 4)
            .confirmationDialog("删除“\(subtask.title)”？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除子任务", role: .destructive) {
                    checklist.delete(subtask.id, parent: parent, hostID: hostID, workspaceID: workspaceID)
                }
            }
    }
}

private struct ChecklistCheckmark: View {
    let title: String
    let completed: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .light)).foregroundStyle(completed ? ashAccent : Color.secondary)
                .frame(width: 24, height: 28)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(completed ? "已完成" : "未完成")
            .help(completed ? "标记为未完成" : "标记为完成")
    }
}

private struct ChecklistTitleField: View {
    let title: String
    let completed: Bool
    let save: (String) -> Bool
    @State private var draft: String
    @FocusState private var focused: Bool
    init(title: String, completed: Bool, save: @escaping (String) -> Bool) {
        self.title = title
        self.completed = completed
        self.save = save
        _draft = State(initialValue: title)
    }
    var body: some View {
        TextField("任务名称", text: $draft, axis: .vertical).textFieldStyle(.plain)
            .font(.system(size: 12)).lineLimit(1...5).strikethrough(completed && !focused)
            .foregroundStyle(completed ? .secondary : .primary).focused($focused)
            .onSubmit { if commit() { focused = false } }
            .onChange(of: focused) { _, value in if !value { _ = commit() } }
            .onChange(of: title) { _, value in if !focused { draft = value } }
            .onExitCommand {
                draft = title
                focused = false
            }
            .accessibilityLabel("编辑任务名称：\(title)")
    }
    private func commit() -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draft = title
            return true
        }
        if trimmed == title { return true }
        return save(trimmed)
    }
}
