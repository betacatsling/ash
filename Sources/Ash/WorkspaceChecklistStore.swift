import Combine
import Foundation

struct ChecklistSubtask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var completed = false
}

struct ChecklistTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var completed = false
    var subtasks: [ChecklistSubtask] = []
    var completedSubtasks: Int { subtasks.filter(\.completed).count }
}

struct WorkspaceChecklist: Codable, Equatable {
    let hostID: String
    let workspaceID: String
    var tasks: [ChecklistTask] = []
}

/// Human-authored tasks are independent of terminal sessions and runtime snapshots.
@MainActor final class WorkspaceChecklistStore: ObservableObject {
    @Published private(set) var lists: [WorkspaceChecklist] = []
    @Published private(set) var error: String?
    private let storage: JSONFileStore<[WorkspaceChecklist]>
    private var readable = true

    init(directory: URL? = nil) {
        storage = JSONFileStore(
            url: (directory ?? AppPaths.dataDirectory).appendingPathComponent("workspace-tasks.json"))
        reload()
    }

    func reload() {
        do {
            lists = try storage.load() ?? []
            readable = true
            error = nil
        } catch {
            readable = false
            self.error = "无法读取任务清单，原文件已保留。\(error.localizedDescription)"
        }
    }

    func tasks(hostID: String, workspaceID: String) -> [ChecklistTask] {
        lists.first { $0.hostID == hostID && $0.workspaceID == workspaceID }?.tasks ?? []
    }

    @discardableResult
    func update(hostID: String, workspaceID: String, _ change: (inout [ChecklistTask]) -> Void) -> Bool {
        guard readable else { return false }
        var next = lists
        if !next.contains(where: { $0.hostID == hostID && $0.workspaceID == workspaceID }) {
            next.append(WorkspaceChecklist(hostID: hostID, workspaceID: workspaceID))
        }
        let index = next.firstIndex { $0.hostID == hostID && $0.workspaceID == workspaceID }!
        change(&next[index].tasks)
        do {
            try storage.save(next)
            lists = next
            error = nil
            return true
        } catch {
            self.error = "任务未能保存，请重试。\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func add(_ title: String, parent: UUID? = nil, hostID: String, workspaceID: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        if let parent, !tasks(hostID: hostID, workspaceID: workspaceID).contains(where: { $0.id == parent }) {
            return false
        }
        return update(hostID: hostID, workspaceID: workspaceID) { tasks in
            if let parent {
                guard let index = tasks.firstIndex(where: { $0.id == parent }) else { return }
                tasks[index].subtasks.append(ChecklistSubtask(title: title))
                tasks[index].completed = false
            } else {
                tasks.append(ChecklistTask(title: title))
            }
        }
    }

    func toggle(_ id: UUID, parent: UUID? = nil, hostID: String, workspaceID: String) {
        update(hostID: hostID, workspaceID: workspaceID) { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == (parent ?? id) }) else { return }
            if parent != nil {
                guard let child = tasks[index].subtasks.firstIndex(where: { $0.id == id }) else { return }
                tasks[index].subtasks[child].completed.toggle()
                tasks[index].completed = tasks[index].subtasks.allSatisfy(\.completed)
            } else {
                let completed = !tasks[index].completed
                tasks[index].completed = completed
                for child in tasks[index].subtasks.indices { tasks[index].subtasks[child].completed = completed }
            }
        }
    }

    @discardableResult
    func rename(_ id: UUID, title: String, parent: UUID? = nil, hostID: String, workspaceID: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        return update(hostID: hostID, workspaceID: workspaceID) { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == (parent ?? id) }) else { return }
            if parent != nil {
                guard let child = tasks[index].subtasks.firstIndex(where: { $0.id == id }) else { return }
                tasks[index].subtasks[child].title = title
            } else {
                tasks[index].title = title
            }
        }
    }

    func delete(_ id: UUID, parent: UUID? = nil, hostID: String, workspaceID: String) {
        update(hostID: hostID, workspaceID: workspaceID) { tasks in
            if let parent, let index = tasks.firstIndex(where: { $0.id == parent }) {
                tasks[index].subtasks.removeAll { $0.id == id }
                if !tasks[index].subtasks.isEmpty {
                    tasks[index].completed = tasks[index].subtasks.allSatisfy(\.completed)
                }
            } else if parent == nil {
                tasks.removeAll { $0.id == id }
            }
        }
    }

    func move(_ id: UUID, offset: Int, parent: UUID? = nil, hostID: String, workspaceID: String) {
        update(hostID: hostID, workspaceID: workspaceID) { tasks in
            if let parent, let index = tasks.firstIndex(where: { $0.id == parent }),
                let child = tasks[index].subtasks.firstIndex(where: { $0.id == id }),
                tasks[index].subtasks.indices.contains(child + offset)
            {
                tasks[index].subtasks.swapAt(child, child + offset)
            } else if parent == nil, let index = tasks.firstIndex(where: { $0.id == id }) {
                let siblings = tasks.indices.filter { tasks[$0].completed == tasks[index].completed }
                if let position = siblings.firstIndex(of: index), siblings.indices.contains(position + offset) {
                    tasks.swapAt(index, siblings[position + offset])
                }
            }
        }
    }
}
