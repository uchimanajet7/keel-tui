import Foundation

public struct TerminalSnapshotCell: Equatable {
    public var text: String
    public var displayWidth: Int
    public var isContinuation: Bool
    public var style: TerminalStyle

    public init(
        text: String,
        displayWidth: Int,
        isContinuation: Bool,
        style: TerminalStyle = .plain
    ) {
        self.text = text
        self.displayWidth = displayWidth
        self.isContinuation = isContinuation
        self.style = style
    }

    static var space: TerminalSnapshotCell {
        TerminalSnapshotCell(text: " ", displayWidth: 1, isContinuation: false)
    }
}

public struct TerminalSnapshot: Equatable {
    public var size: TerminalSize
    public var lines: [String]
    public var cells: [[TerminalSnapshotCell]]

    public init(size: TerminalSize, lines: [String], cells: [[TerminalSnapshotCell]]? = nil) {
        self.size = size
        self.lines = lines
        self.cells = cells ?? lines.map { Self.cells(from: $0, width: size.width) }
    }

    public var text: String {
        lines.joined(separator: "\n")
    }

    public var ansiText: String {
        cells.map(Self.ansiLine).joined(separator: "\n")
    }

    public func line(_ index: Int) -> String {
        lines[index]
    }

    public func displayWidthOfLine(_ index: Int) -> Int {
        TerminalDisplayWidth.width(of: lines[index])
    }

    public func style(column: Int, line: Int) -> TerminalStyle? {
        guard cells.indices.contains(line), cells[line].indices.contains(column) else {
            return nil
        }
        return cells[line][column].style
    }

    private static func cells(from line: String, width: Int) -> [TerminalSnapshotCell] {
        var cells: [TerminalSnapshotCell] = []
        cells.reserveCapacity(width)

        for character in line {
            let characterWidth = TerminalDisplayWidth.width(of: character)
            guard characterWidth > 0 else { continue }
            let clampedWidth = min(characterWidth, 2)
            guard cells.count + clampedWidth <= width else { break }
            cells.append(TerminalSnapshotCell(text: String(character), displayWidth: clampedWidth, isContinuation: false))
            if clampedWidth == 2 {
                cells.append(TerminalSnapshotCell(text: "", displayWidth: 0, isContinuation: true))
            }
        }

        if cells.count < width {
            cells.append(contentsOf: Array(repeating: .space, count: width - cells.count))
        }
        return cells
    }

    private static func ansiLine(_ row: [TerminalSnapshotCell]) -> String {
        var currentStyle = TerminalStyle.plain
        var output = ""

        for cell in row where !cell.isContinuation {
            if cell.style != currentStyle {
                output += transition(from: currentStyle, to: cell.style)
                currentStyle = cell.style
            }
            output += cell.text
        }

        if currentStyle != .plain {
            output += EscapeSequence.resetAttributes
        }
        return output
    }

    private static func transition(from currentStyle: TerminalStyle, to nextStyle: TerminalStyle) -> String {
        if currentStyle == .plain {
            return nextStyle.escapeSequence
        }
        if nextStyle == .plain {
            return EscapeSequence.resetAttributes
        }
        return EscapeSequence.resetAttributes + nextStyle.escapeSequence
    }
}

public struct TerminalCanvas {
    private struct CanvasCell {
        var text: String
        var displayWidth: Int
        var isContinuation: Bool
        var style: TerminalStyle

        static var space: CanvasCell {
            CanvasCell(text: " ", displayWidth: 1, isContinuation: false, style: .plain)
        }

        static func primary(_ text: String, displayWidth: Int, style: TerminalStyle) -> CanvasCell {
            CanvasCell(text: text, displayWidth: displayWidth, isContinuation: false, style: style)
        }

        static func continuation(style: TerminalStyle) -> CanvasCell {
            CanvasCell(text: "", displayWidth: 0, isContinuation: true, style: style)
        }

        var snapshotCell: TerminalSnapshotCell {
            TerminalSnapshotCell(text: text, displayWidth: displayWidth, isContinuation: isContinuation, style: style)
        }
    }

    public let size: TerminalSize
    private var cells: [[CanvasCell]]

    public init(size: TerminalSize) {
        self.size = size
        self.cells = Array(
            repeating: Array(repeating: .space, count: size.width),
            count: size.height
        )
    }

    public mutating func draw(
        _ text: String,
        column: Int,
        line: Int,
        maxWidth: Int? = nil,
        style: TerminalStyle = .plain
    ) {
        guard line >= 0, line < size.height else { return }
        let allowedWidth = max(0, maxWidth ?? (size.width - column))
        guard allowedWidth > 0 else { return }

        let maxColumnExclusive = min(size.width, column + allowedWidth)
        var currentColumn = column

        for character in text {
            let characterWidth = TerminalDisplayWidth.width(of: character)
            guard characterWidth > 0 else { continue }
            let clampedWidth = min(characterWidth, 2)

            if currentColumn + clampedWidth > maxColumnExclusive {
                break
            }
            if currentColumn >= 0 && currentColumn + clampedWidth <= size.width {
                setCell(String(character), displayWidth: clampedWidth, column: currentColumn, line: line, style: style)
            }
            currentColumn += clampedWidth
        }
    }

    public mutating func clear(frame: TerminalFrame) {
        guard !frame.isEmpty else { return }

        let minColumn = max(0, frame.minColumn)
        let maxColumn = min(size.width - 1, frame.maxColumn)
        let minLine = max(0, frame.minLine)
        let maxLine = min(size.height - 1, frame.maxLine)
        guard minColumn <= maxColumn, minLine <= maxLine else { return }

        for line in minLine ... maxLine {
            for column in minColumn ... maxColumn {
                clearCell(column: column, line: line)
            }
        }
    }

    public mutating func drawBox(
        frame: TerminalFrame,
        title: String? = nil,
        focused: Bool = false,
        style: TerminalBoxStyle = .unicode
    ) {
        guard frame.width >= 2, frame.height >= 2 else { return }

        let glyphs = focused ? style.focused : style.normal
        let borderStyle = focused ? style.focusedStyle : style.normalStyle

        draw(String(glyphs.topLeft), column: frame.column, line: frame.line, maxWidth: 1, style: borderStyle)
        draw(String(glyphs.topRight), column: frame.maxColumn, line: frame.line, maxWidth: 1, style: borderStyle)
        draw(String(glyphs.bottomLeft), column: frame.column, line: frame.maxLine, maxWidth: 1, style: borderStyle)
        draw(String(glyphs.bottomRight), column: frame.maxColumn, line: frame.maxLine, maxWidth: 1, style: borderStyle)

        if frame.width > 2 {
            let topBottom = String(repeating: String(glyphs.horizontal), count: frame.width - 2)
            draw(topBottom, column: frame.column + 1, line: frame.line, maxWidth: frame.width - 2, style: borderStyle)
            draw(topBottom, column: frame.column + 1, line: frame.maxLine, maxWidth: frame.width - 2, style: borderStyle)
        }

        if frame.height > 2 {
            for row in (frame.line + 1) ..< frame.maxLine {
                draw(String(glyphs.vertical), column: frame.column, line: row, maxWidth: 1, style: borderStyle)
                draw(String(glyphs.vertical), column: frame.maxColumn, line: row, maxWidth: 1, style: borderStyle)
            }
        }

        if let title {
            drawTitle(title, focused: focused, frame: frame, style: style)
        }
    }

    private mutating func drawTitle(
        _ title: String,
        focused: Bool,
        frame: TerminalFrame,
        style: TerminalBoxStyle
    ) {
        let prefix = focused ? style.focusedTitlePrefix : style.titlePrefix
        let titleStyle = focused ? style.focusedTitleStyle : style.titleStyle
        switch style.titlePlacement {
        case .border:
            draw(
                " \(prefix)\(title) ",
                column: frame.column + 2,
                line: frame.line,
                maxWidth: max(0, frame.width - 4),
                style: titleStyle
            )
        case .firstContentLine:
            let contentFrame = frame.insetBy(columns: 1, lines: 1)
            guard contentFrame.height > 0 else { return }
            draw(
                "\(prefix)\(title)",
                column: contentFrame.column,
                line: contentFrame.line,
                maxWidth: contentFrame.width,
                style: titleStyle
            )
        }
    }

    public func snapshot() -> TerminalSnapshot {
        var lines: [String] = []
        lines.reserveCapacity(size.height)

        for line in 0 ..< size.height {
            var text = ""
            var column = 0
            while column < size.width {
                let cell = cells[line][column]
                if !cell.isContinuation {
                    text += cell.text
                }
                column += 1
            }
            lines.append(text)
        }

        return TerminalSnapshot(size: size, lines: lines, cells: cells.map { row in row.map(\.snapshotCell) })
    }

    private mutating func setCell(_ text: String, displayWidth: Int, column: Int, line: Int, style: TerminalStyle) {
        guard contains(column: column, line: line) else { return }
        clearCell(column: column, line: line)

        if displayWidth == 2 {
            guard contains(column: column + 1, line: line) else { return }
            clearCell(column: column + 1, line: line)
            cells[line][column] = .primary(text, displayWidth: displayWidth, style: style)
            cells[line][column + 1] = .continuation(style: style)
        } else {
            cells[line][column] = .primary(text, displayWidth: displayWidth, style: style)
        }
    }

    private mutating func clearCell(column: Int, line: Int) {
        guard contains(column: column, line: line) else { return }

        if cells[line][column].isContinuation, column > 0 {
            cells[line][column - 1] = .space
        }
        if cells[line][column].displayWidth == 2, contains(column: column + 1, line: line) {
            cells[line][column + 1] = .space
        }
        if column > 0, cells[line][column - 1].displayWidth == 2 {
            cells[line][column - 1] = .space
        }

        cells[line][column] = .space
    }

    private func contains(column: Int, line: Int) -> Bool {
        column >= 0 && column < size.width && line >= 0 && line < size.height
    }
}

public enum TerminalBoxTitlePlacement: Equatable, Sendable {
    case border
    case firstContentLine
}

public struct TerminalBoxGlyphs: Equatable, Sendable {
    public var topLeft: Character
    public var topRight: Character
    public var bottomLeft: Character
    public var bottomRight: Character
    public var horizontal: Character
    public var vertical: Character

    public init(
        topLeft: Character,
        topRight: Character,
        bottomLeft: Character,
        bottomRight: Character,
        horizontal: Character,
        vertical: Character
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

public struct TerminalBoxStyle: Equatable, Sendable {
    public var normal: TerminalBoxGlyphs
    public var focused: TerminalBoxGlyphs
    public var titlePrefix: String
    public var focusedTitlePrefix: String
    public var titlePlacement: TerminalBoxTitlePlacement
    public var normalStyle: TerminalStyle
    public var focusedStyle: TerminalStyle
    public var titleStyle: TerminalStyle
    public var focusedTitleStyle: TerminalStyle

    public init(
        normal: TerminalBoxGlyphs,
        focused: TerminalBoxGlyphs,
        titlePrefix: String,
        focusedTitlePrefix: String,
        titlePlacement: TerminalBoxTitlePlacement,
        normalStyle: TerminalStyle = .plain,
        focusedStyle: TerminalStyle = .plain,
        titleStyle: TerminalStyle = .plain,
        focusedTitleStyle: TerminalStyle = .plain
    ) {
        self.normal = normal
        self.focused = focused
        self.titlePrefix = titlePrefix
        self.focusedTitlePrefix = focusedTitlePrefix
        self.titlePlacement = titlePlacement
        self.normalStyle = normalStyle
        self.focusedStyle = focusedStyle
        self.titleStyle = titleStyle
        self.focusedTitleStyle = focusedTitleStyle
    }

    public static let unicode = TerminalBoxStyle(
        normal: TerminalBoxGlyphs(
            topLeft: "┌",
            topRight: "┐",
            bottomLeft: "└",
            bottomRight: "┘",
            horizontal: "─",
            vertical: "│"
        ),
        focused: TerminalBoxGlyphs(
            topLeft: "┏",
            topRight: "┓",
            bottomLeft: "┗",
            bottomRight: "┛",
            horizontal: "━",
            vertical: "┃"
        ),
        titlePrefix: "",
        focusedTitlePrefix: "● ",
        titlePlacement: .border
    )

    public static let unicodeContentTitle = TerminalBoxStyle(
        normal: TerminalBoxGlyphs(
            topLeft: "┌",
            topRight: "┐",
            bottomLeft: "└",
            bottomRight: "┘",
            horizontal: "─",
            vertical: "│"
        ),
        focused: TerminalBoxGlyphs(
            topLeft: "┏",
            topRight: "┓",
            bottomLeft: "┗",
            bottomRight: "┛",
            horizontal: "━",
            vertical: "┃"
        ),
        titlePrefix: "  ",
        focusedTitlePrefix: "● ",
        titlePlacement: .firstContentLine
    )
}
