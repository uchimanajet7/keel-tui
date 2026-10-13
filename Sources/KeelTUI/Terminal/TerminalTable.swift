import Foundation

public enum TerminalTableAlignment: Equatable, Sendable {
    case leading
    case trailing
}

public enum TerminalTableOverflow: Equatable, Sendable {
    case truncateEnd
    case truncateMiddle
}

public struct TerminalTableColumn: Equatable, Sendable {
    public var header: String
    public var width: Int
    public var alignment: TerminalTableAlignment
    public var overflow: TerminalTableOverflow

    public init(
        header: String,
        width: Int,
        alignment: TerminalTableAlignment = .leading,
        overflow: TerminalTableOverflow = .truncateEnd
    ) {
        self.header = header
        self.width = width
        self.alignment = alignment
        self.overflow = overflow
    }
}

public struct TerminalTableCell: Equatable, Sendable {
    public var text: String
    public var style: TerminalStyle?

    public init(_ text: String, style: TerminalStyle? = nil) {
        self.text = text
        self.style = style
    }
}

public struct TerminalTableRow: Equatable, Sendable {
    public var cells: [TerminalTableCell]
    public var style: TerminalStyle

    public init(cells: [TerminalTableCell], style: TerminalStyle = .plain) {
        self.cells = cells
        self.style = style
    }
}

public struct TerminalTable: Equatable, Sendable {
    public var columns: [TerminalTableColumn]
    public var rows: [TerminalTableRow]
    public var columnSpacing: Int
    public var headerStyle: TerminalStyle
    public var selectedRowIndex: Int?
    public var selectedRowStyle: TerminalStyle
    public var selectionMarker: String
    public var selectionGutterWidth: Int
    /// The body scrollbar; the fixed header is excluded from its viewport.
    public var scrollbar: TerminalScrollbar

    public init(
        columns: [TerminalTableColumn],
        rows: [TerminalTableRow],
        columnSpacing: Int = 2,
        headerStyle: TerminalStyle = .plain,
        selectedRowIndex: Int? = nil,
        selectedRowStyle: TerminalStyle = TerminalStyle(isReversed: true),
        selectionMarker: String = "›",
        selectionGutterWidth: Int = 2,
        scrollbar: TerminalScrollbar = TerminalScrollbar()
    ) {
        self.columns = columns
        self.rows = rows
        self.columnSpacing = columnSpacing
        self.headerStyle = headerStyle
        self.selectedRowIndex = selectedRowIndex
        self.selectedRowStyle = selectedRowStyle
        self.selectionMarker = selectionMarker
        self.selectionGutterWidth = selectionGutterWidth
        self.scrollbar = scrollbar
    }

    /// Resolves record-row units below the fixed header, independently of selection.
    public func layout(in frame: TerminalFrame, rowOffset: Int = 0, maxRows: Int? = nil) -> TerminalScrollLayout {
        let height = max(0, frame.height - 1)
        let body = TerminalFrame(column: frame.column, line: frame.line + min(1, frame.height),
                                 width: columns.isEmpty ? 0 : frame.width, height: min(height, max(0, maxRows ?? height)))
        return scrollbar.layout(in: body, contentLength: rows.count, offset: rowOffset)
    }

    /// Draws the fixed header and normalized body, returning the state for subsequent movement.
    @discardableResult
    public func draw(
        on canvas: inout TerminalCanvas,
        frame: TerminalFrame,
        rowOffset: Int = 0,
        maxRows: Int? = nil
    ) -> TerminalScrollLayout {
        let layout = layout(in: frame, rowOffset: rowOffset, maxRows: maxRows)
        guard !frame.isEmpty, !columns.isEmpty else { return layout }

        canvas.clear(frame: frame)
        let content = TerminalFrame(column: frame.column, line: frame.line,
                                    width: layout.contentFrame.width, height: frame.height)
        drawHeader(on: &canvas, frame: content)

        for (visibleOffset, rowIndex) in layout.state.visibleRange.enumerated() {
            drawRow(
                rows[rowIndex],
                rowIndex: rowIndex,
                on: &canvas,
                frame: content,
                line: frame.line + 1 + visibleOffset
            )
        }
        scrollbar.draw(on: &canvas, frame: layout.scrollbarFrame, state: layout.state)
        return layout
    }

    private func drawHeader(on canvas: inout TerminalCanvas, frame: TerminalFrame) {
        drawCells(
            columns.map { column in
                TerminalTableCell(column.header, style: headerStyle)
            },
            rowStyle: headerStyle,
            on: &canvas,
            frame: frame,
            line: frame.line,
            gutterText: ""
        )
    }

    private func drawRow(
        _ row: TerminalTableRow,
        rowIndex: Int,
        on canvas: inout TerminalCanvas,
        frame: TerminalFrame,
        line: Int
    ) {
        let isSelected = selectedRowIndex == rowIndex
        let rowStyle = isSelected ? selectedRowStyle : row.style
        drawCells(
            row.cells,
            rowStyle: rowStyle,
            on: &canvas,
            frame: frame,
            line: line,
            gutterText: isSelected ? selectionMarker : ""
        )
    }

    private func drawCells(
        _ cells: [TerminalTableCell],
        rowStyle: TerminalStyle,
        on canvas: inout TerminalCanvas,
        frame: TerminalFrame,
        line: Int,
        gutterText: String
    ) {
        guard line >= frame.line, line <= frame.maxLine else { return }

        var column = frame.column
        if selectionGutterWidth > 0 {
            let gutter = fit(
                gutterText,
                width: selectionGutterWidth,
                alignment: .leading,
                overflow: .truncateEnd
            )
            canvas.draw(gutter, column: column, line: line, maxWidth: min(selectionGutterWidth, frame.width), style: rowStyle)
            column += selectionGutterWidth
        }

        for (index, tableColumn) in columns.enumerated() {
            guard column < frame.column + frame.width else { break }
            let cell = index < cells.count ? cells[index] : TerminalTableCell("")
            let text = fit(
                cell.text,
                width: tableColumn.width,
                alignment: tableColumn.alignment,
                overflow: tableColumn.overflow
            )
            let remainingWidth = max(0, frame.column + frame.width - column)
            canvas.draw(
                text,
                column: column,
                line: line,
                maxWidth: min(tableColumn.width, remainingWidth),
                style: cell.style ?? rowStyle
            )
            column += tableColumn.width

            if index < columns.count - 1 {
                let remainingSpacingWidth = max(0, frame.column + frame.width - column)
                canvas.draw(
                    String(repeating: " ", count: columnSpacing),
                    column: column,
                    line: line,
                    maxWidth: min(columnSpacing, remainingSpacingWidth),
                    style: rowStyle
                )
                column += columnSpacing
            }
        }
    }

    private func fit(
        _ text: String,
        width: Int,
        alignment: TerminalTableAlignment,
        overflow: TerminalTableOverflow
    ) -> String {
        guard width > 0 else { return "" }
        let truncated: String
        switch overflow {
        case .truncateEnd:
            truncated = TerminalDisplayWidth.truncate(text, toWidth: width)
        case .truncateMiddle:
            truncated = truncateMiddle(text, toWidth: width)
        }

        let padding = max(0, width - TerminalDisplayWidth.width(of: truncated))
        switch alignment {
        case .leading:
            return truncated + String(repeating: " ", count: padding)
        case .trailing:
            return String(repeating: " ", count: padding) + truncated
        }
    }

    private func truncateMiddle(_ text: String, toWidth width: Int) -> String {
        guard width > 0 else { return "" }
        guard TerminalDisplayWidth.width(of: text) > width else { return text }
        guard width > 1 else { return TerminalDisplayWidth.truncate(text, toWidth: width) }

        let ellipsis = "…"
        let sideWidth = max(0, width - TerminalDisplayWidth.width(of: ellipsis))
        let leadingWidth = (sideWidth + 1) / 2
        let trailingWidth = sideWidth / 2
        let leading = TerminalDisplayWidth.truncate(text, toWidth: leadingWidth)
        let trailing = suffix(of: text, fittingWidth: trailingWidth)
        return leading + ellipsis + trailing
    }

    private func suffix(of text: String, fittingWidth width: Int) -> String {
        guard width > 0 else { return "" }

        var result = ""
        var currentWidth = 0
        for character in text.reversed() {
            let characterWidth = TerminalDisplayWidth.width(of: character)
            if currentWidth + characterWidth > width {
                break
            }
            result.insert(character, at: result.startIndex)
            currentWidth += characterWidth
        }
        return result
    }
}
