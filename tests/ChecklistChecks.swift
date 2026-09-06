import Foundation

@main struct ChecklistChecks {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ash-checklist-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceChecklistStore(directory: directory)
        let host = "local", workspace = "work"
        func tasks() -> [ChecklistTask] { store.tasks(hostID: host, workspaceID: workspace) }
        precondition(!store.add(" \n ", hostID: host, workspaceID: workspace))
        precondition(store.add("  Build sidebar  ", hostID: host, workspaceID: workspace))
        let parent = tasks()[0].id
        precondition(tasks()[0].title == "Build sidebar")
        store.add("Files", parent: parent, hostID: host, workspaceID: workspace)
        store.add("Tasks", parent: parent, hostID: host, workspaceID: workspace)
        let children = tasks()[0].subtasks.map(\.id)
        precondition(!store.add("Third level", parent: children[0], hostID: host, workspaceID: workspace))
        store.toggle(children[0], parent: parent, hostID: host, workspaceID: workspace)
        precondition(!tasks()[0].completed && tasks()[0].completedSubtasks == 1)
        store.toggle(children[1], parent: parent, hostID: host, workspaceID: workspace)
        precondition(tasks()[0].completed)
        store.toggle(parent, hostID: host, workspaceID: workspace)
        precondition(!tasks()[0].completed && tasks()[0].completedSubtasks == 0)
        store.toggle(parent, hostID: host, workspaceID: workspace)
        precondition(tasks()[0].completed && tasks()[0].completedSubtasks == 2)
        store.add("Review", parent: parent, hostID: host, workspaceID: workspace)
        precondition(!tasks()[0].completed)
        store.rename(children[0], title: "File browser", parent: parent, hostID: host, workspaceID: workspace)
        store.move(children[0], offset: 1, parent: parent, hostID: host, workspaceID: workspace)
        precondition(tasks()[0].subtasks[1].title == "File browser")
        store.add("Other workspace", hostID: host, workspaceID: "other")
        store.add("Other host", hostID: "remote", workspaceID: workspace)
        let reopened = WorkspaceChecklistStore(directory: directory)
        precondition(reopened.tasks(hostID: host, workspaceID: workspace) == tasks())
        precondition(reopened.tasks(hostID: "remote", workspaceID: workspace).count == 1)
        precondition(reopened.tasks(hostID: host, workspaceID: "other").count == 1)
        store.delete(children[0], parent: parent, hostID: host, workspaceID: workspace)
        precondition(tasks()[0].subtasks.count == 2)
        store.delete(parent, hostID: host, workspaceID: workspace)
        precondition(WorkspaceChecklistStore(directory: directory).tasks(hostID: host, workspaceID: workspace).isEmpty)
        let file = directory.appendingPathComponent("workspace-tasks.json")
        try Data("corrupt".utf8).write(to: file)
        let damaged = WorkspaceChecklistStore(directory: directory)
        precondition(damaged.error != nil)
        precondition(!damaged.add("Must not overwrite", hostID: host, workspaceID: workspace))
        let original = try String(contentsOf: file, encoding: .utf8)
        precondition(original == "corrupt")
        let blocked = WorkspaceChecklistStore(directory: file)
        precondition(!blocked.add("Cannot save", hostID: host, workspaceID: workspace))
        precondition(blocked.tasks(hostID: host, workspaceID: workspace).isEmpty && blocked.error != nil)
        print("PASS: two-level tasks, completion propagation, editing/reordering/deletion, restart recovery, workspace/host isolation, and safe persistence failures")
    }
}
