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
    public var isEnabled: Bool
    public var shortcutStyle: TerminalStyle?
    public var labelStyle: TerminalStyle?

    public init(
        shortcut: String,
        label: String,
        isEnabled: Bool = true,
        shortcutStyle: TerminalStyle? = nil,
        labelStyle: TerminalStyle? = nil
    ) {
        self.shortcut = shortcut
        self.label = label
        self.isEnabled = isEnabled
        self.shortcutStyle = shortcutStyle
        self.labelStyle = labelStyle
    }
}

public struct TerminalStatusBar: Equatable {
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
        let visibleItems = items.filter(\.isEnabled)
        let content = visibleItems.map { "\($0.shortcut) \($0.label)" }.joined(separator: "  ")
        return TerminalDisplayWidth.padRight(" \(content) ", toWidth: width)
    }

    public func draw(on canvas: inout TerminalCanvas, frame: TerminalFrame) {
        guard frame.height > 0 else { return }
        canvas.draw(
            String(repeating: " ", count: max(0, frame.width)),
            column: frame.column,
            line: frame.line,
            maxWidth: frame.width,
            style: backgroundStyle
        )

        var column = frame.column
        column += drawSegment(" ", style: backgroundStyle, on: &canvas, frame: frame, column: column)

        let visibleItems = items.filter(\.isEnabled)
        for (index, item) in visibleItems.enumerated() {
            if index > 0 {
                column += drawSegment("  ", style: backgroundStyle, on: &canvas, frame: frame, column: column)
            }
            column += drawSegment(item.shortcut, style: item.shortcutStyle ?? shortcutStyle, on: &canvas, frame: frame, column: column)
            column += drawSegment(" ", style: backgroundStyle, on: &canvas, frame: frame, column: column)
            column += drawSegment(item.label, style: item.labelStyle ?? labelStyle, on: &canvas, frame: frame, column: column)
        }
    }

    private func drawSegment(
        _ text: String,
        style: TerminalStyle,
        on canvas: inout TerminalCanvas,
        frame: TerminalFrame,
        column: Int
    ) -> Int {
        let remainingWidth = frame.column + frame.width - column
        guard remainingWidth > 0 else { return 0 }
        let segmentWidth = TerminalDisplayWidth.width(of: text)
        let width = min(segmentWidth, remainingWidth)
        canvas.draw(text, column: column, line: frame.line, maxWidth: width, style: style)
        return width
    }
}
