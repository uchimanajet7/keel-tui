import Foundation

public struct TerminalModalLine: Equatable {
    private var storedSegments: [TerminalStyledTextSegment]
    private var emptyStyle: TerminalStyle
    public var continuationIndent: String
    public var continuationIndentStyle: TerminalStyle

    public var segments: [TerminalStyledTextSegment] {
        get { storedSegments }
        set {
            storedSegments = newValue
            if let firstStyle = newValue.first?.style {
                emptyStyle = firstStyle
            }
        }
    }

    public var text: String {
        get { storedSegments.map(\.text).joined() }
        set { storedSegments = [TerminalStyledTextSegment(newValue, style: style)] }
    }

    public var style: TerminalStyle {
        get { storedSegments.first?.style ?? emptyStyle }
        set {
            emptyStyle = newValue
            storedSegments = storedSegments.map {
                TerminalStyledTextSegment($0.text, style: newValue)
            }
        }
    }

    public init(
        text: String,
        style: TerminalStyle = .plain,
        continuationIndent: String = "",
        continuationIndentStyle: TerminalStyle? = nil
    ) {
        self.storedSegments = [TerminalStyledTextSegment(text, style: style)]
        self.emptyStyle = style
        self.continuationIndent = continuationIndent
        self.continuationIndentStyle = continuationIndentStyle ?? style
    }

    public init(
        segments: [TerminalStyledTextSegment],
        continuationIndent: String = "",
        continuationIndentStyle: TerminalStyle? = nil
    ) {
        self.storedSegments = segments
        self.emptyStyle = segments.first?.style ?? .plain
        self.continuationIndent = continuationIndent
        self.continuationIndentStyle = continuationIndentStyle ?? segments.first?.style ?? .plain
    }
}

public struct TerminalModalLayout: Equatable {
    public let frame: TerminalFrame
    /// The shared layout; its state uses wrapped display rows.
    public let scroll: TerminalScrollLayout
    public let wrappedLines: [TerminalModalLine]
    public let naturalHeight: Int
    public var contentFrame: TerminalFrame { scroll.contentFrame }
    public var visibleLines: [TerminalModalLine] { Array(wrappedLines[visibleRange]) }
    public var totalLineCount: Int { scroll.state.contentLength }
    public var visibleRange: Range<Int> { scroll.state.visibleRange }
    public var scrollOffset: Int { scroll.state.offset }
    public var maximumScrollOffset: Int { scroll.state.maximumOffset }

    /// Creates layout metadata whose visible rows derive from the shared state.
    public init(
        frame: TerminalFrame,
        scroll: TerminalScrollLayout,
        wrappedLines: [TerminalModalLine],
        naturalHeight: Int
    ) {
        self.frame = frame
        self.scroll = scroll
        self.wrappedLines = wrappedLines
        self.naturalHeight = naturalHeight
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
    public var preferredHeight: Int?
    public var minimumHeight: Int
    public var maximumHeight: Int
    public var scrollOffset: Int
    public var horizontalPadding: Int
    public var verticalPadding: Int
    public var style: TerminalBoxStyle
    public var contentStyle: TerminalStyle
    public var focused: Bool
    public var clearsRowsAcrossArea: Bool
    /// Configures the indicator independently from focus and modal styling.
    public var scrollbar: TerminalScrollbar

    public init(
        title: String,
        lines: [String],
        preferredWidth: Int? = nil,
        minimumWidth: Int = 28,
        maximumWidth: Int = 72,
        preferredHeight: Int? = nil,
        minimumHeight: Int = 3,
        maximumHeight: Int = .max,
        scrollOffset: Int = 0,
        horizontalPadding: Int = 1,
        verticalPadding: Int = 0,
        style: TerminalBoxStyle = .unicode,
        contentStyle: TerminalStyle = .plain,
        focused: Bool = true,
        clearsRowsAcrossArea: Bool = true,
        scrollbar: TerminalScrollbar = TerminalScrollbar()
    ) {
        self.title = title
        self.styledLines = lines.map { TerminalModalLine(text: $0, style: contentStyle) }
        self.preferredWidth = preferredWidth
        self.minimumWidth = max(2, minimumWidth)
        self.maximumWidth = max(2, maximumWidth)
        self.preferredHeight = preferredHeight
        self.minimumHeight = max(2, minimumHeight)
        self.maximumHeight = max(2, maximumHeight)
        self.scrollOffset = max(0, scrollOffset)
        self.horizontalPadding = max(0, horizontalPadding)
        self.verticalPadding = max(0, verticalPadding)
        self.style = style
        self.contentStyle = contentStyle
        self.focused = focused
        self.clearsRowsAcrossArea = clearsRowsAcrossArea
        self.scrollbar = scrollbar
    }

    public init(
        title: String,
        styledLines: [TerminalModalLine],
        preferredWidth: Int? = nil,
        minimumWidth: Int = 28,
        maximumWidth: Int = 72,
        preferredHeight: Int? = nil,
        minimumHeight: Int = 3,
        maximumHeight: Int = .max,
        scrollOffset: Int = 0,
        horizontalPadding: Int = 1,
        verticalPadding: Int = 0,
        style: TerminalBoxStyle = .unicode,
        contentStyle: TerminalStyle = .plain,
        focused: Bool = true,
        clearsRowsAcrossArea: Bool = true,
        scrollbar: TerminalScrollbar = TerminalScrollbar()
    ) {
        self.title = title
        self.styledLines = styledLines
        self.preferredWidth = preferredWidth
        self.minimumWidth = max(2, minimumWidth)
        self.maximumWidth = max(2, maximumWidth)
        self.preferredHeight = preferredHeight
        self.minimumHeight = max(2, minimumHeight)
        self.maximumHeight = max(2, maximumHeight)
        self.scrollOffset = max(0, scrollOffset)
        self.horizontalPadding = max(0, horizontalPadding)
        self.verticalPadding = max(0, verticalPadding)
        self.style = style
        self.contentStyle = contentStyle
        self.focused = focused
        self.clearsRowsAcrossArea = clearsRowsAcrossArea
        self.scrollbar = scrollbar
    }

    public func frame(in size: TerminalSize) -> TerminalFrame {
        layout(in: size).frame
    }

    public func frame(in area: TerminalFrame) -> TerminalFrame {
        layout(in: area).frame
    }

    public func layout(in size: TerminalSize) -> TerminalModalLayout {
        layout(in: TerminalFrame(column: 0, line: 0, width: size.width, height: size.height))
    }

    /// Resolves the modal within its size bounds, wrapping at the shared final content width.
    /// Stable gutters contribute to natural width. Automatic gutters preserve the existing
    /// natural outer width and reserve the bar and spacing inside it only on overflow.
    public func layout(in area: TerminalFrame) -> TerminalModalLayout {
        guard !area.isEmpty else {
            let emptyFrame = TerminalFrame(column: area.column, line: area.line, width: 0, height: 0)
            let wrappedLines = TerminalTextLayout.wrap(styledLines, width: 0)
            return TerminalModalLayout(
                frame: emptyFrame,
                scroll: scrollbar.layout(in: emptyFrame, contentLength: wrappedLines.count, offset: scrollOffset),
                wrappedLines: wrappedLines,
                naturalHeight: 0
            )
        }

        let boundedMinimumWidth = min(maximumWidth, minimumWidth)
        let titleWidth = TerminalDisplayWidth.width(of: title) + 4
        let contentWidth = styledLines.map { TerminalDisplayWidth.width(of: $0.text) }.max() ?? 0
        let widthLimit = min(area.width, maximumWidth)
        let sizingBody = TerminalFrame(column: 0, line: 0, width: widthLimit, height: area.height)
            .contentFrame(titlePlacement: style.titlePlacement)
            .insetBy(columns: horizontalPadding, lines: verticalPadding)
        let sizingScroll = scrollbar.layout(in: sizingBody, contentLength: 0)
        let reservedWidth = sizingBody.width - sizingScroll.contentFrame.width
        let baseWidth = min(widthLimit, contentWidth + horizontalPadding * 2 + 2)
        let naturalWidth = max(boundedMinimumWidth, titleWidth,
                               baseWidth + min(reservedWidth, widthLimit - baseWidth))
        let requestedWidth = preferredWidth ?? naturalWidth
        let width = min(area.width, min(maximumWidth, max(boundedMinimumWidth, requestedWidth)))

        let titleContentRows: Int
        switch style.titlePlacement {
        case .border:
            titleContentRows = 0
        case .firstContentLine:
            titleContentRows = 1
        }
        func resolve(reservingGutter: Bool) -> TerminalModalLayout {
            let measuringBody = TerminalFrame(column: 0, line: 0, width: width, height: area.height)
                .contentFrame(titlePlacement: style.titlePlacement)
                .insetBy(columns: horizontalPadding, lines: verticalPadding)
            var wrappedLines: [TerminalModalLine] = []
            _ = scrollbar.layout(in: measuringBody, reservingGutter: reservingGutter) { contentWidth in
                wrappedLines = TerminalTextLayout.wrap(styledLines, width: contentWidth)
                return wrappedLines.count
            }
            let naturalHeight = max(3, wrappedLines.count + verticalPadding * 2 + 2 + titleContentRows)
            let boundedMinimumHeight = min(maximumHeight, minimumHeight)
            let height = min(area.height, min(maximumHeight, max(boundedMinimumHeight, preferredHeight ?? naturalHeight)))
            let frame = TerminalFrame(
                column: area.column + max(0, (area.width - width) / 2),
                line: area.line + max(0, (area.height - height) / 2), width: width, height: height
            )
            let body = frame.contentFrame(titlePlacement: style.titlePlacement)
                .insetBy(columns: horizontalPadding, lines: verticalPadding)
            return TerminalModalLayout(
                frame: frame,
                scroll: scrollbar.layout(in: body, offset: scrollOffset, reservingGutter: reservingGutter) { _ in
                    wrappedLines.count
                },
                wrappedLines: wrappedLines, naturalHeight: naturalHeight
            )
        }
        let first = resolve(reservingGutter: scrollbar.gutter == .stable)
        if scrollbar.gutter == .automatic, scrollbar.visibility == .whenNeeded,
           first.totalLineCount > first.contentFrame.height {
            return resolve(reservingGutter: true)
        }
        return first
    }

    /// Moves from the resolved display-row position at the current available size.
    public mutating func scroll(_ movement: TerminalScrollMovement, in area: TerminalFrame) {
        var state = layout(in: area).scroll.state
        state.move(movement)
        scrollOffset = state.offset
    }

    /// Draws the modal using an optional normal surface background, independently of text styles.
    public func draw(on canvas: inout TerminalCanvas, background: Color? = nil) {
        draw(on: &canvas, in: TerminalFrame(column: 0, line: 0, width: canvas.size.width, height: canvas.size.height),
             background: background)
    }

    /// Draws within the caller's area; `background` also fills padding and content spacing.
    public func draw(on canvas: inout TerminalCanvas, in area: TerminalFrame, background: Color? = nil) {
        let layout = layout(in: area)
        let modalFrame = layout.frame
        guard modalFrame.width >= 2, modalFrame.height >= 2 else { return }

        let clearFrame = clearsRowsAcrossArea
            ? TerminalFrame(column: area.column, line: modalFrame.line, width: area.width, height: modalFrame.height)
            : modalFrame
        canvas.clear(frame: clearFrame, style: TerminalStyle(background: background))
        canvas.drawBox(frame: modalFrame, title: title, focused: focused, style: style)
        scrollbar.draw(on: &canvas, layout: layout.scroll, background: background)

        let contentFrame = layout.contentFrame
        guard contentFrame.width > 0, contentFrame.height > 0 else { return }

        for (offset, line) in layout.visibleLines.enumerated() {
            draw(line, on: &canvas, column: contentFrame.column, line: contentFrame.line + offset,
                 maxWidth: contentFrame.width, background: background)
        }
    }

    private func draw(
        _ line: TerminalModalLine,
        on canvas: inout TerminalCanvas,
        column: Int,
        line row: Int,
        maxWidth: Int,
        background: Color?
    ) {
        var currentColumn = column
        let maximumColumn = column + max(0, maxWidth)
        for segment in line.segments {
            let remainingWidth = maximumColumn - currentColumn
            guard remainingWidth > 0 else { break }
            canvas.draw(
                segment.text,
                column: currentColumn,
                line: row,
                maxWidth: remainingWidth,
                style: segment.style.background(segment.style.background ?? background)
            )
            currentColumn += TerminalDisplayWidth.width(of: segment.text)
        }
    }
}
