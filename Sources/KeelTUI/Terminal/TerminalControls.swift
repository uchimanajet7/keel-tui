import Foundation

public struct TerminalListRow: Equatable {
    public var index: Int
    public var text: String
    public var isSelected: Bool

    public init(index: Int, text: String, isSelected: Bool) {
        self.index = index
        self.text = text
        self.isSelected = isSelected
    }
}

public struct TerminalSelectableList: Equatable {
    public var rows: [String]
    public var selectedIndex: Int
    public var scrollOffset: Int

    public init(rows: [String], selectedIndex: Int = 0, scrollOffset: Int = 0) {
        self.rows = rows
        self.selectedIndex = rows.isEmpty ? 0 : min(max(0, selectedIndex), rows.count - 1)
        self.scrollOffset = max(0, scrollOffset)
    }

    public mutating func handle(_ key: TerminalKey) {
        switch key {
        case .arrowDown:
            moveSelection(by: 1)
        case .arrowUp:
            moveSelection(by: -1)
        case .home:
            moveToStart()
        case .end:
            moveToEnd()
        case .pageDown:
            moveSelection(by: max(1, visibleStep))
        case .pageUp:
            moveSelection(by: -max(1, visibleStep))
        case .character(let character) where character == "j":
            moveSelection(by: 1)
        case .character(let character) where character == "k":
            moveSelection(by: -1)
        default:
            break
        }
    }

    public mutating func moveSelection(by delta: Int) {
        guard !rows.isEmpty else {
            selectedIndex = 0
            scrollOffset = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex + delta), rows.count - 1)
    }

    public mutating func moveToStart() {
        selectedIndex = rows.isEmpty ? 0 : 0
    }

    public mutating func moveToEnd() {
        selectedIndex = max(0, rows.count - 1)
    }

    public func visibleRows(height: Int) -> [TerminalListRow] {
        guard height > 0, !rows.isEmpty else { return [] }
        let offset = normalizedScrollOffset(height: height)
        let end = min(rows.count, offset + height)
        return (offset ..< end).map {
            TerminalListRow(index: $0, text: rows[$0], isSelected: $0 == selectedIndex)
        }
    }

    public func normalizedScrollOffset(height: Int) -> Int {
        guard height > 0, !rows.isEmpty else { return 0 }
        var offset = min(max(0, scrollOffset), max(0, rows.count - height))
        if selectedIndex < offset {
            offset = selectedIndex
        } else if selectedIndex >= offset + height {
            offset = selectedIndex - height + 1
        }
        return offset
    }

    private var visibleStep: Int {
        max(1, rows.isEmpty ? 1 : min(10, rows.count))
    }
}

public struct TerminalTextViewport: Equatable {
    public var lines: [String]
    public var scrollOffset: Int

    public init(lines: [String], scrollOffset: Int = 0) {
        self.lines = lines
        self.scrollOffset = max(0, scrollOffset)
    }

    public mutating func append(_ line: String) {
        lines.append(line)
    }

    public mutating func handle(_ key: TerminalKey) {
        switch key {
        case .arrowDown:
            scroll(by: 1)
        case .arrowUp:
            scroll(by: -1)
        case .home:
            scrollOffset = 0
        case .end:
            scrollOffset = max(0, lines.count - 1)
        case .pageDown:
            scroll(by: 10)
        case .pageUp:
            scroll(by: -10)
        case .character(let character) where character == "j":
            scroll(by: 1)
        case .character(let character) where character == "k":
            scroll(by: -1)
        default:
            break
        }
    }

    public mutating func scroll(by delta: Int) {
        scrollOffset = max(0, scrollOffset + delta)
    }

    public mutating func scrollToBottom(height: Int) {
        scrollOffset = max(0, lines.count - max(0, height))
    }

    public func visibleLines(height: Int) -> [String] {
        guard height > 0, !lines.isEmpty else { return [] }
        let offset = min(max(0, scrollOffset), max(0, lines.count - height))
        let end = min(lines.count, offset + height)
        return Array(lines[offset ..< end])
    }
}

public struct TerminalFocusCoordinator: Equatable {
    public var sections: [TerminalPaneID]
    public var activeSection: TerminalPaneID

    public init(sections: [TerminalPaneID], activeSection: TerminalPaneID? = nil) {
        self.sections = sections
        self.activeSection = activeSection ?? sections.first ?? TerminalPaneID(rawValue: "")
    }

    public mutating func handle(_ key: TerminalKey) -> Bool {
        guard key == .tab else { return false }
        activateNextSection()
        return true
    }

    public mutating func activateNextSection() {
        guard !sections.isEmpty else { return }
        guard let index = sections.firstIndex(of: activeSection) else {
            activeSection = sections[0]
            return
        }
        activeSection = sections[(index + 1) % sections.count]
    }

    public mutating func activatePreviousSection() {
        guard !sections.isEmpty else { return }
        guard let index = sections.firstIndex(of: activeSection) else {
            activeSection = sections[0]
            return
        }
        activeSection = sections[index == 0 ? sections.count - 1 : index - 1]
    }
}

public struct TerminalStatusBarItem: Equatable {
    public var shortcut: String
    public var label: String
    public var compactLabel: String?
    public var retentionPriority: Int
    public var isVisible: Bool
    public var isEnabled: Bool
    public var shortcutStyle: TerminalStyle?
    public var labelStyle: TerminalStyle?

    public init(
        shortcut: String,
        label: String,
        compactLabel: String? = nil,
        retentionPriority: Int = 0,
        isVisible: Bool = true,
        isEnabled: Bool = true,
        shortcutStyle: TerminalStyle? = nil,
        labelStyle: TerminalStyle? = nil
    ) {
        self.shortcut = shortcut
        self.label = label
        self.compactLabel = compactLabel
        self.retentionPriority = retentionPriority
        self.isVisible = isVisible
        self.isEnabled = isEnabled
        self.shortcutStyle = shortcutStyle
        self.labelStyle = labelStyle
    }
}

public struct TerminalStatusBar: Equatable {
    private struct ResolvedItem {
        var item: TerminalStatusBarItem
        var label: String

        var width: Int {
            TerminalDisplayWidth.width(of: item.shortcut) + 1 + TerminalDisplayWidth.width(of: label)
        }
    }

    private struct ResolvedLayout {
        var items: [ResolvedItem]

        var content: String {
            guard !items.isEmpty else { return "" }
            return " " + items.map { "\($0.item.shortcut) \($0.label)" }.joined(separator: "  ") + " "
        }
    }

    public var items: [TerminalStatusBarItem]
    public var shortcutStyle: TerminalStyle
    public var labelStyle: TerminalStyle
    public var backgroundStyle: TerminalStyle

    public init(
        items: [TerminalStatusBarItem],
        shortcutStyle: TerminalStyle = .plain,
        labelStyle: TerminalStyle = .plain,
        backgroundStyle: TerminalStyle = .plain
    ) {
        self.items = items
        self.shortcutStyle = shortcutStyle
        self.labelStyle = labelStyle
        self.backgroundStyle = backgroundStyle
    }

    public func text(width: Int) -> String {
        guard width > 0 else { return "" }
        return TerminalDisplayWidth.padRight(resolvedLayout(width: width).content, toWidth: width)
    }

    public func draw(on canvas: inout TerminalCanvas, frame: TerminalFrame) {
        guard frame.height > 0, frame.width > 0 else { return }
        canvas.draw(
            String(repeating: " ", count: max(0, frame.width)),
            column: frame.column,
            line: frame.line,
            maxWidth: frame.width,
            style: backgroundStyle
        )

        let layout = resolvedLayout(width: frame.width)
        guard !layout.items.isEmpty else { return }

        var column = frame.column + 1
        for (index, resolved) in layout.items.enumerated() {
            if index > 0 {
                canvas.draw("  ", column: column, line: frame.line, maxWidth: 2, style: backgroundStyle)
                column += 2
            }
            let shortcutWidth = TerminalDisplayWidth.width(of: resolved.item.shortcut)
            canvas.draw(
                resolved.item.shortcut,
                column: column,
                line: frame.line,
                maxWidth: shortcutWidth,
                style: resolved.item.shortcutStyle ?? shortcutStyle
            )
            column += shortcutWidth
            canvas.draw(" ", column: column, line: frame.line, maxWidth: 1, style: backgroundStyle)
            column += 1
            let labelWidth = TerminalDisplayWidth.width(of: resolved.label)
            canvas.draw(
                resolved.label,
                column: column,
                line: frame.line,
                maxWidth: labelWidth,
                style: resolved.item.labelStyle ?? labelStyle
            )
            column += labelWidth
        }
    }

    private func resolvedLayout(width: Int) -> ResolvedLayout {
        guard width > 0 else { return ResolvedLayout(items: []) }

        let candidates = items.filter { $0.isVisible && $0.isEnabled }
        guard !candidates.isEmpty else { return ResolvedLayout(items: []) }

        var labels = candidates.map(\.label)
        var retained = Array(repeating: true, count: candidates.count)
        let overflowOrder = candidates.indices.sorted { lhs, rhs in
            if candidates[lhs].retentionPriority == candidates[rhs].retentionPriority {
                return lhs > rhs
            }
            return candidates[lhs].retentionPriority < candidates[rhs].retentionPriority
        }

        func measuredWidth() -> Int {
            let indices = candidates.indices.filter { retained[$0] }
            guard !indices.isEmpty else { return 0 }
            let itemWidth = indices.reduce(0) { partial, index in
                partial
                    + TerminalDisplayWidth.width(of: candidates[index].shortcut)
                    + 1
                    + TerminalDisplayWidth.width(of: labels[index])
            }
            return 2 + itemWidth + max(0, indices.count - 1) * 2
        }

        if measuredWidth() > width {
            for index in overflowOrder {
                guard let compactLabel = candidates[index].compactLabel else { continue }
                guard TerminalDisplayWidth.width(of: compactLabel) < TerminalDisplayWidth.width(of: labels[index]) else {
                    continue
                }
                labels[index] = compactLabel
                if measuredWidth() <= width {
                    break
                }
            }
        }

        if measuredWidth() > width {
            for index in overflowOrder {
                retained[index] = false
                if measuredWidth() <= width {
                    break
                }
            }
        }

        guard measuredWidth() <= width else { return ResolvedLayout(items: []) }
        return ResolvedLayout(
            items: candidates.indices.compactMap { index in
                guard retained[index] else { return nil }
                return ResolvedItem(item: candidates[index], label: labels[index])
            }
        )
    }
}
