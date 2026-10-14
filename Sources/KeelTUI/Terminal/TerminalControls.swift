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

/// Caller-owned single-row items with independent selection and viewing positions.
public struct TerminalSelectableList: Equatable {
    /// Item text; drawing clips each item to one row at the usable content width.
    public var rows: [String]
    /// The selected item index; call `revealSelection()` after assigning it to reveal it.
    public var selectedIndex: Int
    /// The first viewed item, normalized and saved when measuring or moving.
    public var scrollOffset: Int
    /// Indicator configuration; each list item occupies one unwrapped display row.
    public var scrollbar: TerminalScrollbar
    private var viewportHeight = 0
    private var selectionNeedsReveal = true

    /// Creates a list; a nonzero initial selection is revealed unless an offset was supplied.
    public init(rows: [String], selectedIndex: Int = 0, scrollOffset: Int = 0,
                scrollbar: TerminalScrollbar = TerminalScrollbar()) {
        self.rows = rows
        self.selectedIndex = rows.isEmpty ? 0 : min(max(0, selectedIndex), rows.count - 1)
        self.scrollOffset = max(0, scrollOffset)
        self.scrollbar = scrollbar
        self.selectionNeedsReveal = selectedIndex != 0 && scrollOffset == 0
    }

    /// Moves selection using the most recently measured viewport, or the supplied frame.
    public mutating func handle(_ key: TerminalKey, in frame: TerminalFrame? = nil) {
        if let frame { _ = layout(in: frame) }
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
            moveSelection(by: viewportHeight)
        case .pageUp:
            moveSelection(by: -viewportHeight)
        case .character(let character) where character == "j":
            moveSelection(by: 1)
        case .character(let character) where character == "k":
            moveSelection(by: -1)
        default:
            break
        }
    }

    /// Moves selection without wrapping, and reveals the resulting selected item.
    public mutating func moveSelection(by delta: Int) {
        var selection = TerminalScrollState(contentLength: rows.count, viewportLength: 1, offset: selectedIndex)
        selection.move(.units(delta))
        selectedIndex = selection.offset
        revealSelection()
    }

    /// Selects and reveals the first item.
    public mutating func moveToStart() {
        selectedIndex = 0
        revealSelection()
    }

    /// Selects and reveals the last item.
    public mutating func moveToEnd() {
        selectedIndex = max(0, rows.count - 1)
        revealSelection()
    }

    /// Slices single-row items and saves the normalized offset for the next input.
    public mutating func visibleRows(height: Int) -> [TerminalListRow] {
        let state = resolve(height: height)
        return state.visibleRange.map {
            TerminalListRow(index: $0, text: rows[$0], isSelected: $0 == selectedIndex)
        }
    }

    /// Normalizes and saves the viewing position without changing selection.
    public mutating func normalizedScrollOffset(height: Int) -> Int {
        resolve(height: height).offset
    }

    /// Resolves the content frame and viewport in single-row item units.
    public mutating func layout(in frame: TerminalFrame) -> TerminalScrollLayout {
        var layout = scrollbar.layout(in: frame, contentLength: rows.count, offset: scrollOffset)
        layout.state = resolve(height: layout.state.viewportLength)
        return layout
    }

    /// Moves only the viewing position, leaving the selected item unchanged.
    public mutating func scroll(_ movement: TerminalScrollMovement, in frame: TerminalFrame? = nil) {
        selectionNeedsReveal = false
        var state = frame.map { layout(in: $0).state } ?? resolve(height: viewportHeight)
        state.move(movement)
        scrollOffset = state.offset
    }

    /// Explicitly requests that the selected row become visible.
    public mutating func revealSelection() {
        selectionNeedsReveal = true
        _ = resolve(height: viewportHeight)
    }

    /// Draws clipped single-row items and an indicator in separate columns.
    /// `background` is the normal surface color, independent of row and selection styles.
    @discardableResult
    public mutating func draw(on canvas: inout TerminalCanvas, frame: TerminalFrame,
                              style: TerminalStyle = .plain,
                              selectedStyle: TerminalStyle = TerminalStyle(isReversed: true),
                              background: Color? = nil) -> TerminalScrollLayout {
        let layout = layout(in: frame)
        canvas.clear(frame: frame, style: TerminalStyle(background: background))
        for (row, index) in layout.state.visibleRange.enumerated() {
            let text = rows[index].split(maxSplits: 1, omittingEmptySubsequences: false,
                                         whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
            let rowStyle = index == selectedIndex ? selectedStyle : style
            canvas.draw(text, column: layout.contentFrame.column, line: layout.contentFrame.line + row,
                        maxWidth: layout.contentFrame.width,
                        style: rowStyle.background(rowStyle.background ?? background))
        }
        scrollbar.draw(on: &canvas, layout: layout, background: background)
        return layout
    }

    private mutating func resolve(height: Int) -> TerminalScrollState {
        viewportHeight = max(0, height)
        selectedIndex = min(max(0, selectedIndex), max(0, rows.count - 1))
        var state = TerminalScrollState(contentLength: rows.count, viewportLength: viewportHeight, offset: scrollOffset)
        if selectionNeedsReveal, viewportHeight > 0 {
            if !rows.isEmpty { state.move(.reveal(selectedIndex ..< selectedIndex + 1)) }
            selectionNeedsReveal = false
        }
        scrollOffset = state.offset
        return state
    }
}

/// Wrapped text and the shared layout used to slice and draw it.
public struct TerminalTextViewportLayout: Equatable {
    /// All display rows after wrapping at the final content width.
    public let wrappedLines: [String]
    /// Content/spacing/scrollbar geometry and the normalized display-row state.
    public let scroll: TerminalScrollLayout
    /// The display rows in the normalized visible range.
    public var visibleLines: [String] { Array(wrappedLines[scroll.state.visibleRange]) }
}

/// A caller-owned viewport that wraps plain text or slices already laid-out rows.
public struct TerminalTextViewport: Equatable {
    /// Logical input lines for frame-based wrapping, or display rows for height-only slicing.
    public var lines: [String]
    /// The first display row, normalized and saved when measuring or moving.
    public var scrollOffset: Int
    /// Indicator, gutter, and content spacing for frame-based wrapping and drawing.
    public var scrollbar: TerminalScrollbar
    private var viewportHeight = 0
    private var lastFrame: TerminalFrame?

    /// Creates a viewport; measure or draw it before requesting viewport-sized movement.
    public init(lines: [String], scrollOffset: Int = 0, scrollbar: TerminalScrollbar = TerminalScrollbar()) {
        self.lines = lines
        self.scrollOffset = max(0, scrollOffset)
        self.scrollbar = scrollbar
    }

    /// Appends content without automatically following its end.
    public mutating func append(_ line: String) {
        lines.append(line)
    }

    /// Applies navigation after resolving the current content and viewport dimensions.
    /// Pass a frame on resize; otherwise the most recent measurement is reused.
    public mutating func handle(_ key: TerminalKey, in frame: TerminalFrame? = nil) {
        if let frame { _ = layout(in: frame) }
        switch key {
        case .arrowDown:
            scroll(by: 1)
        case .arrowUp:
            scroll(by: -1)
        case .home:
            scroll(.start)
        case .end:
            scroll(.end)
        case .pageDown:
            scroll(.pages(1))
        case .pageUp:
            scroll(.pages(-1))
        case .character(let character) where character == "j":
            scroll(by: 1)
        case .character(let character) where character == "k":
            scroll(by: -1)
        default:
            break
        }
    }

    /// Moves by display rows using the last measured viewport.
    public mutating func scroll(by delta: Int) {
        scroll(.units(delta))
    }

    /// Moves in display rows using the last measurement, optionally resolving a new frame first.
    public mutating func scroll(_ movement: TerminalScrollMovement, in frame: TerminalFrame? = nil) {
        var state: TerminalScrollState
        if let frame = frame ?? lastFrame {
            state = layout(in: frame).scroll.state
        } else {
            state = TerminalScrollState(contentLength: lines.count, viewportLength: viewportHeight, offset: scrollOffset)
        }
        state.move(movement)
        scrollOffset = state.offset
    }

    /// Moves to the end of already laid-out rows, replacing any remembered wrapped frame.
    public mutating func scrollToBottom(height: Int) {
        _ = visibleLines(height: height)
        scroll(.end)
    }

    /// Slices already laid-out rows without wrapping and saves the normalized offset.
    public mutating func visibleLines(height: Int) -> [String] {
        lastFrame = nil
        viewportHeight = max(0, height)
        let state = TerminalScrollState(contentLength: lines.count, viewportLength: viewportHeight, offset: scrollOffset)
        scrollOffset = state.offset
        return Array(lines[state.visibleRange])
    }

    /// Allocates the scrollbar and spacing before wrapping at the final content width.
    public mutating func layout(in frame: TerminalFrame) -> TerminalTextViewportLayout {
        var wrapped: [String] = []
        let input = lines.map { TerminalModalLine(text: $0) }
        let layout = scrollbar.layout(in: frame, offset: scrollOffset) { width in
            wrapped = TerminalTextLayout.wrap(input, width: width).map(\.text)
            return wrapped.count
        }
        lastFrame = frame
        viewportHeight = layout.state.viewportLength
        scrollOffset = layout.state.offset
        return TerminalTextViewportLayout(wrappedLines: wrapped, scroll: layout)
    }

    /// Draws wrapped rows and the indicator without overlapping the content.
    /// `background` fills the normal surface; `style` applies to the text only.
    @discardableResult
    public mutating func draw(on canvas: inout TerminalCanvas, frame: TerminalFrame,
                              style: TerminalStyle = .plain, background: Color? = nil) -> TerminalTextViewportLayout {
        let layout = layout(in: frame)
        canvas.clear(frame: frame, style: TerminalStyle(background: background))
        for (row, text) in layout.visibleLines.enumerated() {
            canvas.draw(text, column: layout.scroll.contentFrame.column, line: layout.scroll.contentFrame.line + row,
                        maxWidth: layout.scroll.contentFrame.width, style: style.background(style.background ?? background))
        }
        scrollbar.draw(on: &canvas, layout: layout.scroll, background: background)
        return layout
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
