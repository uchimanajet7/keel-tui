import Foundation

public struct TerminalModalLine: Equatable {
    public var text: String
    public var style: TerminalStyle

    public init(text: String, style: TerminalStyle = .plain) {
        self.text = text
        self.style = style
    }
}

public struct TerminalModal: Equatable {
    public var title: String
    public var styledLines: [TerminalModalLine]
    public var lines: [String] {
        get {
            styledLines.map(\.text)
        }
        set {
            styledLines = newValue.map { TerminalModalLine(text: $0, style: contentStyle) }
        }
    }
    public var preferredWidth: Int?
    public var minimumWidth: Int
    public var maximumWidth: Int
    public var horizontalPadding: Int
    public var verticalPadding: Int
    public var style: TerminalBoxStyle
    public var contentStyle: TerminalStyle
    public var focused: Bool
    public var clearsRowsAcrossArea: Bool

    public init(
        title: String,
        lines: [String],
        preferredWidth: Int? = nil,
        minimumWidth: Int = 28,
        maximumWidth: Int = 72,
        horizontalPadding: Int = 1,
        verticalPadding: Int = 0,
        style: TerminalBoxStyle = .unicode,
        contentStyle: TerminalStyle = .plain,
        focused: Bool = true,
        clearsRowsAcrossArea: Bool = true
    ) {
        self.title = title
        self.styledLines = lines.map { TerminalModalLine(text: $0, style: contentStyle) }
        self.preferredWidth = preferredWidth
        self.minimumWidth = max(2, minimumWidth)
        self.maximumWidth = max(2, maximumWidth)
        self.horizontalPadding = max(0, horizontalPadding)
        self.verticalPadding = max(0, verticalPadding)
        self.style = style
        self.contentStyle = contentStyle
        self.focused = focused
        self.clearsRowsAcrossArea = clearsRowsAcrossArea
    }

    public init(
        title: String,
        styledLines: [TerminalModalLine],
        preferredWidth: Int? = nil,
        minimumWidth: Int = 28,
        maximumWidth: Int = 72,
        horizontalPadding: Int = 1,
        verticalPadding: Int = 0,
        style: TerminalBoxStyle = .unicode,
        contentStyle: TerminalStyle = .plain,
        focused: Bool = true,
        clearsRowsAcrossArea: Bool = true
    ) {
        self.title = title
        self.styledLines = styledLines
        self.preferredWidth = preferredWidth
        self.minimumWidth = max(2, minimumWidth)
        self.maximumWidth = max(2, maximumWidth)
        self.horizontalPadding = max(0, horizontalPadding)
        self.verticalPadding = max(0, verticalPadding)
        self.style = style
        self.contentStyle = contentStyle
        self.focused = focused
        self.clearsRowsAcrossArea = clearsRowsAcrossArea
    }

    public func frame(in size: TerminalSize) -> TerminalFrame {
        frame(in: TerminalFrame(column: 0, line: 0, width: size.width, height: size.height))
    }

    public func frame(in area: TerminalFrame) -> TerminalFrame {
        guard !area.isEmpty else {
            return TerminalFrame(column: area.column, line: area.line, width: 0, height: 0)
        }

        let titleWidth = TerminalDisplayWidth.width(of: title) + 4
        let contentWidth = styledLines.map { TerminalDisplayWidth.width(of: $0.text) }.max() ?? 0
        let naturalWidth = max(minimumWidth, titleWidth, contentWidth + horizontalPadding * 2 + 2)
        let requestedWidth = preferredWidth.map { max(2, $0) } ?? min(maximumWidth, naturalWidth)
        let width = min(area.width, max(2, requestedWidth))

        let naturalHeight = max(3, styledLines.count + verticalPadding * 2 + 2)
        let height = min(area.height, naturalHeight)

        return TerminalFrame(
            column: area.column + max(0, (area.width - width) / 2),
            line: area.line + max(0, (area.height - height) / 2),
            width: width,
            height: height
        )
    }

    public func draw(on canvas: inout TerminalCanvas) {
        draw(on: &canvas, in: TerminalFrame(column: 0, line: 0, width: canvas.size.width, height: canvas.size.height))
    }

    public func draw(on canvas: inout TerminalCanvas, in area: TerminalFrame) {
        let modalFrame = frame(in: area)
        guard modalFrame.width >= 2, modalFrame.height >= 2 else { return }

        let clearFrame = clearsRowsAcrossArea
            ? TerminalFrame(column: area.column, line: modalFrame.line, width: area.width, height: modalFrame.height)
            : modalFrame
        canvas.clear(frame: clearFrame)
        canvas.drawBox(frame: modalFrame, title: title, focused: focused, style: style)

        let contentFrame = modalFrame
            .contentFrame(titlePlacement: style.titlePlacement)
            .insetBy(columns: horizontalPadding, lines: verticalPadding)
        guard contentFrame.width > 0, contentFrame.height > 0 else { return }

        for (offset, line) in styledLines.prefix(contentFrame.height).enumerated() {
            canvas.draw(
                line.text,
                column: contentFrame.column,
                line: contentFrame.line + offset,
                maxWidth: contentFrame.width,
                style: line.style
            )
        }
    }
}
