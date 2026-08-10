import AppKit
@preconcurrency import QuickLookUI
import SwiftUI

enum LogTableContextAction {
    case showInInspector(UUID)
    case showOnlyTag(String)
    case excludeTag(String)
    case showOnlyPID(Int)
    case toggleBookmark(UUID)
    case revealEvidence(UUID)
    case copyEvidencePath(UUID)
    case exportEvidence(UUID)
}

struct LogTableView: NSViewRepresentable {
    let rows: [LogEvent]
    @Binding var selectedIDs: Set<UUID>
    let followLatest: Bool
    let visibleColumns: Set<LogTableColumn>
    let onFollowingChanged: (Bool) -> Void
    let evidenceURL: (UUID) -> URL?
    let onContextAction: (LogTableContextAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedIDs: $selectedIDs,
            onFollowingChanged: onFollowingChanged,
            evidenceURL: evidenceURL,
            onContextAction: onContextAction
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = CopyableLogTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        tableView.copyHandler = { [weak coordinator = context.coordinator] in
            coordinator?.copyRawText(nil)
        }
        tableView.spaceHandler = { [weak coordinator = context.coordinator] in
            coordinator?.previewSelectedEvidence()
        }
        tableView.doubleAction = #selector(Coordinator.openSelectionInInspector(_:))
        tableView.target = context.coordinator
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.autosaveName = "GameLog.LogTable.Columns.v1"
        tableView.autosaveTableColumns = true

        addColumn(to: tableView, id: "time", title: "时间", width: 126, minWidth: 116)
        addColumn(to: tableView, id: "level", title: "级别", width: 52, minWidth: 48)
        addColumn(to: tableView, id: "pid", title: "PID/TID", width: 96, minWidth: 82)
        addColumn(to: tableView, id: "tag", title: "Tag", width: 180, minWidth: 100)
        addColumn(to: tableView, id: "message", title: "消息", width: 560, minWidth: 240)

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.selectedIDsBinding = $selectedIDs
        context.coordinator.onFollowingChanged = onFollowingChanged
        context.coordinator.evidenceURL = evidenceURL
        context.coordinator.onContextAction = onContextAction
        context.coordinator.update(
            rows: rows,
            selectedIDs: selectedIDs,
            followLatest: followLatest,
            visibleColumns: visibleColumns
        )
    }

    private func addColumn(
        to tableView: NSTableView,
        id: String,
        title: String,
        width: CGFloat,
        minWidth: CGFloat
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = minWidth
        tableView.addTableColumn(column)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate,
        @preconcurrency QLPreviewPanelDataSource {
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        var rows: [LogEvent] = []
        var selectedIDsBinding: Binding<Set<UUID>>
        var onFollowingChanged: (Bool) -> Void
        var evidenceURL: (UUID) -> URL?
        var onContextAction: (LogTableContextAction) -> Void
        private var isApplyingSelection = false
        private var isProgrammaticScroll = false
        private var lastReportedFollowing = true
        private var previewURLs: [URL] = []

        init(
            selectedIDs: Binding<Set<UUID>>,
            onFollowingChanged: @escaping (Bool) -> Void,
            evidenceURL: @escaping (UUID) -> URL?,
            onContextAction: @escaping (LogTableContextAction) -> Void
        ) {
            selectedIDsBinding = selectedIDs
            self.onFollowingChanged = onFollowingChanged
            self.evidenceURL = evidenceURL
            self.onContextAction = onContextAction
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard row >= 0, row < rows.count, let tableColumn else { return nil }
            let event = rows[row]
            let identifier = tableColumn.identifier
            let cell: NSTableCellView

            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                label.lineBreakMode = .byTruncatingTail
                label.maximumNumberOfLines = 1
                label.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
                cell.textField = label
                cell.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }

            let value: String
            switch identifier.rawValue {
            case "time":
                value = event.timestampText
            case "level":
                value = event.isMarker ? "◆" : event.level.rawValue
            case "pid":
                let pid = event.pid.map(String.init) ?? "—"
                let tid = event.tid.map(String.init) ?? "—"
                value = "\(pid)/\(tid)"
            case "tag":
                value = event.tag
            default:
                value = event.message.replacingOccurrences(of: "\n", with: "  ↳  ")
            }
            cell.textField?.stringValue = value
            cell.textField?.font = .monospacedSystemFont(
                ofSize: 11.5,
                weight: event.isMarker ? .semibold : .regular
            )
            cell.textField?.textColor = identifier.rawValue == "level"
                ? Self.color(for: event.level)
                : (event.isMarker ? .secondaryLabelColor : .labelColor)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let tableView else { return }
            selectedIDsBinding.wrappedValue = Set(
                tableView.selectedRowIndexes.compactMap { row in
                    rows.indices.contains(row) ? rows[row].id : nil
                }
            )
        }

        @objc func copyRawText(_ sender: Any?) {
            copyToPasteboard(rowsForCurrentSelection().map(\.rawText).joined(separator: "\n"))
        }

        @objc func copyMessage(_ sender: Any?) {
            copyToPasteboard(rowsForCurrentSelection().map(\.message).joined(separator: "\n"))
        }

        @objc func copyStructuredText(_ sender: Any?) {
            let header = "Time\tLevel\tPID\tTID\tTag\tBuffer\tMessage"
            let lines = rowsForCurrentSelection().map { event in
                [
                    event.timestampText,
                    event.level.rawValue,
                    event.pid.map(String.init) ?? "",
                    event.tid.map(String.init) ?? "",
                    event.tag,
                    event.buffer.rawValue,
                    event.message.replacingOccurrences(of: "\t", with: " ")
                ].joined(separator: "\t")
            }
            copyToPasteboard(([header] + lines).joined(separator: "\n"))
        }

        @objc func scrollBoundsDidChange(_ notification: Notification) {
            guard !isProgrammaticScroll,
                  let tableView,
                  let scrollView,
                  !rows.isEmpty else {
                return
            }
            let distanceFromBottom = tableView.bounds.height - scrollView.contentView.bounds.maxY
            let atBottom = distanceFromBottom <= tableView.rowHeight * 2
            guard atBottom != lastReportedFollowing else { return }
            lastReportedFollowing = atBottom
            onFollowingChanged(atBottom)
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let event = rowsForCurrentSelection().first else { return }
            addMenuItem("复制消息", action: #selector(copyMessage(_:)), to: menu)
            addMenuItem("复制原始日志", action: #selector(copyRawText(_:)), to: menu)
            addMenuItem("复制所选多行（结构化）", action: #selector(copyStructuredText(_:)), to: menu)

            if event.isMarker {
                menu.addItem(.separator())
                addMenuItem("在检查器中显示", action: #selector(showInInspector(_:)), to: menu)
                if let evidenceID = event.evidenceID {
                    addMenuItem("快速查看", action: #selector(previewEvidence(_:)), to: menu)
                    addMenuItem("在 Finder 中显示", action: #selector(revealEvidence(_:)), to: menu)
                    addMenuItem("复制文件路径", action: #selector(copyEvidencePath(_:)), to: menu)
                    addMenuItem("导出所选证据…", action: #selector(exportEvidence(_:)), to: menu)
                    if evidenceURL(evidenceID) == nil {
                        for item in menu.items.suffix(4) {
                            item.isEnabled = false
                        }
                    }
                }
            } else {
                menu.addItem(.separator())
                addMenuItem("仅显示此 Tag", action: #selector(showOnlyTag(_:)), to: menu)
                addMenuItem("排除此 Tag", action: #selector(excludeTag(_:)), to: menu)
                addMenuItem("仅显示此 PID", action: #selector(showOnlyPID(_:)), to: menu)
                addMenuItem("添加/取消书签", action: #selector(toggleBookmark(_:)), to: menu)
                menu.item(withTitle: "仅显示此 PID")?.isEnabled = event.pid != nil
            }
        }

        @objc func openSelectionInInspector(_ sender: Any?) {
            guard let event = rowsForCurrentSelection().first else { return }
            onContextAction(.showInInspector(event.id))
        }

        @objc func showInInspector(_ sender: Any?) {
            openSelectionInInspector(sender)
        }

        @objc func showOnlyTag(_ sender: Any?) {
            guard let event = rowsForCurrentSelection().first else { return }
            onContextAction(.showOnlyTag(event.tag))
        }

        @objc func excludeTag(_ sender: Any?) {
            guard let event = rowsForCurrentSelection().first else { return }
            onContextAction(.excludeTag(event.tag))
        }

        @objc func showOnlyPID(_ sender: Any?) {
            guard let pid = rowsForCurrentSelection().first?.pid else { return }
            onContextAction(.showOnlyPID(pid))
        }

        @objc func toggleBookmark(_ sender: Any?) {
            guard let event = rowsForCurrentSelection().first else { return }
            onContextAction(.toggleBookmark(event.id))
        }

        @objc func revealEvidence(_ sender: Any?) {
            guard let evidenceID = rowsForCurrentSelection().first?.evidenceID else { return }
            onContextAction(.revealEvidence(evidenceID))
        }

        @objc func copyEvidencePath(_ sender: Any?) {
            guard let evidenceID = rowsForCurrentSelection().first?.evidenceID else { return }
            onContextAction(.copyEvidencePath(evidenceID))
        }

        @objc func exportEvidence(_ sender: Any?) {
            guard let evidenceID = rowsForCurrentSelection().first?.evidenceID else { return }
            onContextAction(.exportEvidence(evidenceID))
        }

        @objc func previewEvidence(_ sender: Any?) {
            previewSelectedEvidence()
        }

        func previewSelectedEvidence() {
            guard let evidenceID = rowsForCurrentSelection().first?.evidenceID,
                  let url = evidenceURL(evidenceID) else {
                return
            }
            previewURLs = [url]
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.dataSource = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            previewURLs.count
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            guard previewURLs.indices.contains(index) else { return nil }
            return previewURLs[index] as NSURL
        }

        func update(
            rows newRows: [LogEvent],
            selectedIDs: Set<UUID>,
            followLatest: Bool,
            visibleColumns: Set<LogTableColumn>
        ) {
            guard let tableView else { return }
            for column in tableView.tableColumns {
                if let configured = LogTableColumn(rawValue: column.identifier.rawValue) {
                    column.isHidden = !visibleColumns.contains(configured)
                }
            }
            let oldRows = rows
            let shouldFollow = followLatest
                && !newRows.isEmpty
                && (!lastReportedFollowing || newRows.last?.id != oldRows.last?.id)

            if oldRows.isEmpty || newRows.isEmpty {
                rows = newRows
                tableView.reloadData()
            } else if newRows.count >= oldRows.count,
                      newRows.prefix(oldRows.count).elementsEqual(oldRows, by: { $0.id == $1.id }) {
                rows = newRows
                let inserted = IndexSet(integersIn: oldRows.count..<newRows.count)
                if !inserted.isEmpty {
                    tableView.insertRows(at: inserted, withAnimation: [])
                }
            } else if let oldStart = oldRows.firstIndex(where: { $0.id == newRows.first?.id }) {
                let commonCount = min(oldRows.count - oldStart, newRows.count)
                let oldSlice = oldRows[oldStart..<(oldStart + commonCount)]
                let newSlice = newRows[0..<commonCount]
                if oldSlice.elementsEqual(newSlice, by: { $0.id == $1.id }) {
                    rows = newRows
                    tableView.beginUpdates()
                    if oldStart > 0 {
                        tableView.removeRows(
                            at: IndexSet(integersIn: 0..<oldStart),
                            withAnimation: []
                        )
                    }
                    if commonCount < newRows.count {
                        tableView.insertRows(
                            at: IndexSet(integersIn: commonCount..<newRows.count),
                            withAnimation: []
                        )
                    }
                    tableView.endUpdates()
                } else {
                    rows = newRows
                    tableView.reloadData()
                }
            } else if oldRows.map(\.id) != newRows.map(\.id) {
                rows = newRows
                tableView.reloadData()
            }

            applySelection(selectedIDs, in: tableView)
            lastReportedFollowing = followLatest
            if shouldFollow {
                isProgrammaticScroll = true
                tableView.scrollRowToVisible(newRows.count - 1)
                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticScroll = false
                }
            }
        }

        private func applySelection(_ selectedIDs: Set<UUID>, in tableView: NSTableView) {
            let desiredRows = IndexSet(rows.indices.filter { selectedIDs.contains(rows[$0].id) })
            guard tableView.selectedRowIndexes != desiredRows else { return }
            isApplyingSelection = true
            tableView.selectRowIndexes(desiredRows, byExtendingSelection: false)
            isApplyingSelection = false
            if let first = desiredRows.first {
                tableView.scrollRowToVisible(first)
            }
        }

        private func rowsForCurrentSelection() -> [LogEvent] {
            guard let tableView else { return [] }
            return tableView.selectedRowIndexes.compactMap { row in
                rows.indices.contains(row) ? rows[row] : nil
            }
        }

        private func copyToPasteboard(_ text: String) {
            guard !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        private static func color(for level: LogLevel) -> NSColor {
            switch level {
            case .warning: .systemOrange
            case .error, .fatal: .systemRed
            case .info: .systemBlue
            case .debug: .secondaryLabelColor
            case .verbose, .unknown: .tertiaryLabelColor
            }
        }
    }
}

@MainActor
private final class CopyableLogTableView: NSTableView {
    var copyHandler: (() -> Void)?
    var spaceHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            copyHandler?()
            return
        }
        if event.charactersIgnoringModifiers == " " {
            spaceHandler?()
            return
        }
        super.keyDown(with: event)
    }
}
