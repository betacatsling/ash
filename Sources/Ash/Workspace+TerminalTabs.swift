import Foundation

extension Workspace {
    func legacyVisibleLayout(available: [String]) -> TerminalLayout? {
        let ids = legacyVisibleRunIDs(available: available)
        if let layout = terminalLayout?.keeping(Set(ids)), layout.runIDs == ids { return layout }
        return TerminalLayout.horizontal(ids)
    }

    private func legacyVisibleRunIDs(available: [String]) -> [String] {
        let selected = available.first { $0 == selectedRunID } ?? available.last
        let candidates =
            paneRunIDs ?? (split ? [selected, secondaryRunID].compactMap { $0 } : [selected].compactMap { $0 })
        var seen = Set<String>()
        let visible = candidates.filter { available.contains($0) && seen.insert($0).inserted }
        return visible.isEmpty ? [selected].compactMap { $0 } : visible
    }

    func visibleLayout(available: [String]) -> TerminalLayout? {
        activeTerminalTab(available: available)?.layout
    }
    func visibleRunIDs(available: [String]) -> [String] {
        activeTerminalTab(available: available)?.runIDs ?? []
    }

    mutating func setPanes(_ ids: [String], focused: String?) {
        let retained = terminalLayout?.keeping(Set(ids))
        let layout = retained?.runIDs == ids ? retained : TerminalLayout.horizontal(ids)
        if let groups = terminalGroups {
            var tabs = groups.compactMap { $0.keeping(Set($0.runIDs).subtracting(ids)) }
            if let layout {
                tabs.insert(
                    TerminalTabGroup(
                        id: UUID().uuidString, layout: layout,
                        focusedRunID: focused.flatMap { ids.contains($0) ? $0 : nil } ?? ids[0]), at: 0)
            }
            applyTerminalTabs(tabs, focused: focused.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first)
        } else {
            terminalLayout = layout
            paneRunIDs = ids
            selectedRunID = focused.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
            split = ids.count > 1
            secondaryRunID = ids.first { $0 != selectedRunID }
        }
    }

    mutating func selectTerminal(_ id: String, available: [String]) {
        guard available.contains(id) else { return }
        var tabs = terminalTabs(available: available)
        guard let index = tabs.firstIndex(where: { $0.runIDs.contains(id) }) else { return }
        tabs[index].focusedRunID = id
        applyTerminalTabs(tabs, focused: id)
    }

    @discardableResult
    mutating func moveTerminal(
        _ source: String, beside target: String, side: TerminalDropSide,
        available: [String], wholeTab: Bool = false
    ) -> Bool {
        var tabs = terminalTabs(available: available)
        guard source != target,
            let sourceIndex = tabs.firstIndex(where: { $0.runIDs.contains(source) }),
            let targetIndex = tabs.firstIndex(where: { $0.runIDs.contains(target) }),
            !wholeTab || sourceIndex != targetIndex
        else { return false }
        let targetID = tabs[targetIndex].id
        let moving = wholeTab ? tabs[sourceIndex].layout : .pane(source)
        let movedIDs = Set(moving.runIDs)
        tabs = tabs.compactMap { $0.keeping(Set($0.runIDs).subtracting(movedIDs)) }
        guard let index = tabs.firstIndex(where: { $0.id == targetID }) else { return false }
        let pair = TerminalLayout.split(
            id: UUID().uuidString, axis: side.axis, fraction: 0.5,
            first: side.insertsFirst ? moving : .pane(target),
            second: side.insertsFirst ? .pane(target) : moving)
        tabs[index].layout = tabs[index].layout.replacing(target, with: pair)
        tabs[index].focusedRunID = source
        applyTerminalTabs(tabs, focused: source)
        return true
    }

    /// Each session belongs to exactly one page. Legacy visible splits become one page.
    func terminalTabs(available: [String]) -> [TerminalTabGroup] {
        let allowed = Set(available)
        var groups: [TerminalTabGroup] = []
        if let terminalGroups {
            groups = terminalGroups
        } else if let layout = legacyVisibleLayout(available: available) {
            let grouped = Set(layout.runIDs)
            let legacy = TerminalTabGroup(
                id: "tab-\(layout.runIDs[0])", layout: layout,
                focusedRunID: selectedRunID.flatMap { grouped.contains($0) ? $0 : nil } ?? layout.runIDs[0])
            var added = false
            for id in available {
                if grouped.contains(id) {
                    if !added {
                        groups.append(legacy)
                        added = true
                    }
                } else {
                    groups.append(.single(id))
                }
            }
        }
        var seen = Set<String>()
        var seenTabs = Set<String>()
        var result: [TerminalTabGroup] = []
        for group in groups {
            guard var clean = group.keeping(allowed.subtracting(seen)) else { continue }
            if !seenTabs.insert(clean.id).inserted {
                clean.id = "tab-\(clean.runIDs[0])"
                seenTabs.insert(clean.id)
            }
            seen.formUnion(clean.runIDs)
            result.append(clean)
        }
        result += available.filter { seen.insert($0).inserted }.map(TerminalTabGroup.single)
        return result
    }

    func activeTerminalTab(available: [String]) -> TerminalTabGroup? {
        let tabs = terminalTabs(available: available)
        return tabs.first { $0.runIDs.contains(selectedRunID ?? "") } ?? tabs.first
    }

    mutating func applyTerminalTabs(_ tabs: [TerminalTabGroup], focused: String?) {
        terminalGroups = tabs
        guard let group = tabs.first(where: { $0.runIDs.contains(focused ?? "") }) ?? tabs.first else {
            selectedRunID = nil
            secondaryRunID = nil
            paneRunIDs = []
            terminalLayout = nil
            split = false
            return
        }
        selectedRunID = focused.flatMap { group.runIDs.contains($0) ? $0 : nil } ?? group.focusedRunID
        paneRunIDs = group.runIDs
        terminalLayout = group.layout
        split = group.isSplit
        secondaryRunID = group.runIDs.first { $0 != selectedRunID }
    }

    mutating func selectTerminalPage(_ tabID: String, available: [String]) {
        let tabs = terminalTabs(available: available)
        guard let group = tabs.first(where: { $0.id == tabID }) else { return }
        applyTerminalTabs(tabs, focused: group.focusedRunID)
    }

    mutating func removeTerminal(_ id: String, available: [String]) {
        let tabs = terminalTabs(available: available)
        let oldIndex = tabs.firstIndex { $0.runIDs.contains(id) } ?? 0
        let survivors = tabs.compactMap { $0.keeping(Set(available).subtracting([id])) }
        let next =
            survivors.first { $0.runIDs.contains(selectedRunID ?? "") }
            ?? tabs.first(where: { $0.runIDs.contains(id) }).flatMap { old in survivors.first { $0.id == old.id } }
            ?? (survivors.isEmpty ? nil : survivors[min(oldIndex, survivors.count - 1)])
        applyTerminalTabs(survivors, focused: selectedRunID == id ? next?.focusedRunID : selectedRunID)
    }

    mutating func detachTerminal(_ id: String, available: [String], selectDetached: Bool = true, atEnd: Bool = false) {
        var tabs = terminalTabs(available: available)
        guard let index = tabs.firstIndex(where: { $0.runIDs.contains(id) }), tabs[index].isSplit,
            let retained = tabs[index].keeping(Set(tabs[index].runIDs).subtracting([id]))
        else { return }
        tabs[index] = retained
        var single = TerminalTabGroup.single(id)
        if tabs.contains(where: { $0.id == single.id }) { single.id = UUID().uuidString }
        tabs.insert(single, at: atEnd ? tabs.count : index + 1)
        applyTerminalTabs(tabs, focused: selectDetached ? id : retained.focusedRunID)
    }

    mutating func ungroupTerminalTab(_ tabID: String, available: [String]) {
        var tabs = terminalTabs(available: available)
        guard let index = tabs.firstIndex(where: { $0.id == tabID }), tabs[index].isSplit else { return }
        let singles = tabs[index].runIDs.map(TerminalTabGroup.single)
        tabs.replaceSubrange(index...index, with: singles)
        applyTerminalTabs(tabs, focused: selectedRunID)
    }

    mutating func arrangeTerminalTab(_ tabID: String, axis: TerminalSplitAxis, available: [String]) {
        var tabs = terminalTabs(available: available)
        guard let index = tabs.firstIndex(where: { $0.id == tabID }), tabs[index].isSplit else { return }
        tabs[index].layout = TerminalLayout.arranged(tabs[index].runIDs, axis: axis)!
        applyTerminalTabs(tabs, focused: selectedRunID)
    }

    mutating func resizeTerminalSplit(_ id: String, fraction: Double, available: [String]) {
        var tabs = terminalTabs(available: available)
        guard let index = tabs.firstIndex(where: { $0.runIDs.contains(selectedRunID ?? "") }) else { return }
        tabs[index].layout = tabs[index].layout.settingFraction(fraction, for: id)
        applyTerminalTabs(tabs, focused: selectedRunID)
    }
}
