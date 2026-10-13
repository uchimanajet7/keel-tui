/// An input-independent movement in the same units as a scroll state.
public enum TerminalScrollMovement: Equatable, Sendable {
    /// Move by a signed number of content units.
    case units(Int)
    /// Move by a signed number of actual viewport lengths.
    case pages(Int)
    /// Reveal the beginning of the content.
    case start
    /// Reveal the end of the content.
    case end
    /// Minimally reveal a range, or align its start if it exceeds the viewport.
    case reveal(Range<Int>)
}

/// A normalized one-dimensional viewport. All values use the same content unit.
///
/// Use display rows for wrapped text, not source-line or selection indices.
public struct TerminalScrollState: Equatable, Sendable {
    /// The nonnegative total content length.
    public private(set) var contentLength: Int
    /// The nonnegative length available to display scrolling content.
    public private(set) var viewportLength: Int
    /// The normalized first visible position.
    public private(set) var offset: Int

    /// Resolves lengths and clamps an arbitrary requested offset.
    public init(contentLength: Int, viewportLength: Int, offset: Int = 0) {
        self.contentLength = max(0, contentLength)
        self.viewportLength = max(0, viewportLength)
        self.offset = min(max(0, offset), max(0, self.contentLength - self.viewportLength))
    }

    /// The last valid offset, including an empty range when the viewport is zero.
    public var maximumOffset: Int { max(0, contentLength - viewportLength) }
    /// The half-open content range actually visible at the resolved position.
    public var visibleRange: Range<Int> {
        offset ..< offset + min(viewportLength, contentLength - offset)
    }
    /// Whether content exists before the visible range.
    public var hasContentBefore: Bool { offset > 0 }
    /// Whether content exists after the visible range.
    public var hasContentAfter: Bool { visibleRange.upperBound < contentLength }
    /// Whether the content exceeds the viewport.
    public var isScrollable: Bool { contentLength > viewportLength }

    /// Updates measurements and clamps the saved offset before further movement.
    public mutating func update(contentLength: Int, viewportLength: Int) {
        self = Self(contentLength: contentLength, viewportLength: viewportLength, offset: offset)
    }

    /// Applies movement from the normalized position, saturating at the endpoints.
    public mutating func move(_ movement: TerminalScrollMovement) {
        switch movement {
        case .units(let amount):
            let sum = offset.addingReportingOverflow(amount)
            offset = sum.overflow ? (amount > 0 ? maximumOffset : 0) : min(max(0, sum.partialValue), maximumOffset)
        case .pages(let count):
            let amount = viewportLength.multipliedReportingOverflow(by: count)
            move(.units(amount.overflow ? (count > 0 ? Int.max : Int.min) : amount.partialValue))
        case .start:
            offset = 0
        case .end:
            offset = maximumOffset
        case .reveal(let range):
            guard viewportLength > 0 else { return }
            let start = min(max(0, range.lowerBound), contentLength)
            let end = min(max(0, range.upperBound), contentLength)
            guard start < end else { return }
            if end - start > viewportLength || start < offset {
                offset = min(start, maximumOffset)
            } else if end > visibleRange.upperBound {
                offset = min(end - viewportLength, maximumOffset)
            }
        }
    }
}

/// Whether an overflow indicator is drawn. Neither case implies gutter allocation.
public enum TerminalScrollbarVisibility: Equatable, Sendable {
    /// Show overflow immediately, even without focus or prior input.
    case whenNeeded
    /// Do not draw an indicator.
    case hidden
}

/// How the content and scrollbar share the available width.
public enum TerminalScrollbarGutter: Equatable, Sendable {
    /// Allocate a column only when a visible scrollbar is needed.
    case automatic
    /// Always reserve a column, so visibility changes cannot change wrapping.
    case stable
}

/// One-cell glyphs and existing terminal styles for a vertical scrollbar.
public struct TerminalScrollbarStyle: Equatable, Sendable {
    /// The track glyph; it must occupy one display cell.
    public var track: Character
    /// The thumb glyph; it must occupy one display cell.
    public var thumb: Character
    /// Indicates content before the viewport.
    public var before: Character
    /// Indicates content after the viewport.
    public var after: Character
    /// Indicates both directions when only one row is available.
    public var both: Character
    /// Style shared by the track and direction indicators.
    public var trackStyle: TerminalStyle
    /// Style used for the thumb.
    public var thumbStyle: TerminalStyle

    /// Creates an indicator with color-independent glyphs and optional styling.
    public init(
        track: Character = "│", thumb: Character = "█",
        before: Character = "↑", after: Character = "↓", both: Character = "↕",
        trackStyle: TerminalStyle = .plain, thumbStyle: TerminalStyle = .plain
    ) {
        self.track = track
        self.thumb = thumb
        self.before = before
        self.after = after
        self.both = both
        self.trackStyle = trackStyle
        self.thumbStyle = thumbStyle
    }
}

/// Track and thumb row ranges relative to a scrollbar frame, excluding arrow rows.
public struct TerminalScrollbarGeometry: Equatable, Sendable {
    /// Rows occupied by the track.
    public let trackRange: Range<Int>
    /// Rows occupied by the thumb.
    public let thumbRange: Range<Int>

    /// Resolves proportional geometry without overflowing integer multiplication.
    public init(state: TerminalScrollState, length: Int) {
        let length = max(0, length)
        guard state.isScrollable, length >= 3 else {
            trackRange = 0 ..< 0
            thumbRange = 0 ..< 0
            return
        }
        let trackLength = length - 2
        let thumbLength = max(1, Self.scale(min(state.viewportLength, state.contentLength),
                                          by: trackLength, over: state.contentLength))
        let travel = trackLength - thumbLength
        let start = 1 + Self.scale(state.offset, by: travel, over: state.maximumOffset)
        trackRange = 1 ..< length - 1
        thumbRange = start ..< start + thumbLength
    }

    private static func scale(_ value: Int, by length: Int, over total: Int) -> Int {
        guard total > 0 else { return 0 }
        let product = UInt(value).multipliedFullWidth(by: UInt(length))
        return Int(UInt(total).dividingFullWidth(product).quotient)
    }
}

/// The disjoint content and scrollbar frames, with one resolved scroll state.
public struct TerminalScrollLayout: Equatable {
    /// The frame available to content after allocating the gutter.
    public let contentFrame: TerminalFrame
    /// The reserved scrollbar column, even if its indicator is hidden.
    public let scrollbarFrame: TerminalFrame
    /// The normalized measurements used by content, movement, and drawing.
    public internal(set) var state: TerminalScrollState
}

/// Layout and rendering for a vertical scrollbar without input or selection policy.
public struct TerminalScrollbar: Equatable, Sendable {
    /// The drawing policy, independent of focus.
    public var visibility: TerminalScrollbarVisibility
    /// The column reservation policy, independent of visibility.
    public var gutter: TerminalScrollbarGutter
    /// Glyphs and styles used to render the indicator.
    public var style: TerminalScrollbarStyle

    /// Creates a scrollbar that appears on overflow, allocating its own column.
    public init(
        visibility: TerminalScrollbarVisibility = .whenNeeded,
        gutter: TerminalScrollbarGutter = .automatic,
        style: TerminalScrollbarStyle = TerminalScrollbarStyle()
    ) {
        self.visibility = visibility
        self.gutter = gutter
        self.style = style
    }

    /// Resolves a fixed-row content layout, excluding the gutter from its width.
    public func layout(in frame: TerminalFrame, contentLength: Int, offset: Int = 0) -> TerminalScrollLayout {
        layout(in: frame, offset: offset) { _ in contentLength }
    }

    /// Measures content at its final width, remeasuring if an automatic gutter appears.
    /// The closure must return content rows at the supplied width.
    public func layout(
        in frame: TerminalFrame, offset: Int = 0, measure: (Int) -> Int
    ) -> TerminalScrollLayout {
        var reserved = gutter == .stable
        var content = contentFrame(in: frame, reservingGutter: reserved)
        var length = max(0, measure(content.width))
        if !reserved, visibility == .whenNeeded, length > content.height {
            reserved = true
            content = contentFrame(in: frame, reservingGutter: true)
            length = max(0, measure(content.width))
        }
        let bar = TerminalFrame(column: content.column + content.width, line: frame.line,
                                width: reserved && frame.width > 0 ? 1 : 0, height: frame.height)
        return TerminalScrollLayout(
            contentFrame: content, scrollbarFrame: bar,
            state: TerminalScrollState(contentLength: length,
                                       viewportLength: content.width > 0 ? content.height : 0, offset: offset)
        )
    }

    func contentFrame(in frame: TerminalFrame, reservingGutter: Bool) -> TerminalFrame {
        TerminalFrame(column: frame.column, line: frame.line,
                      width: frame.width - (reservingGutter ? 1 : 0), height: frame.height)
    }

    /// Draws only in the supplied scrollbar column; use a layout's scrollbar frame.
    /// A hidden or unnecessary indicator clears its reserved cells.
    public func draw(on canvas: inout TerminalCanvas, frame: TerminalFrame, state: TerminalScrollState) {
        guard !frame.isEmpty else { return }
        let geometry = TerminalScrollbarGeometry(state: state, length: frame.height)
        for row in 0 ..< frame.height {
            let cell = cell(at: row, length: frame.height, state: state, geometry: geometry)
            canvas.draw(String(cell.glyph), column: frame.column, line: frame.line + row,
                        maxWidth: 1, style: cell.style)
        }
    }

    func cell(at row: Int, length: Int, state: TerminalScrollState,
              geometry: TerminalScrollbarGeometry) -> (glyph: Character, style: TerminalStyle) {
        guard visibility == .whenNeeded, state.isScrollable, row >= 0, row < length else {
            return (" ", .plain)
        }
        let glyph: Character
        var cellStyle = style.trackStyle
        if length == 1 {
            glyph = state.hasContentBefore && state.hasContentAfter ? style.both
                : state.hasContentBefore ? style.before : style.after
        } else if row == 0 {
            glyph = state.hasContentBefore ? style.before : " "
        } else if row == length - 1 {
            glyph = state.hasContentAfter ? style.after : " "
        } else if geometry.thumbRange.contains(row) {
            glyph = style.thumb
            cellStyle = style.thumbStyle
        } else {
            glyph = style.track
        }
        // Invalid custom glyphs must never overwrite adjacent content cells.
        return (TerminalDisplayWidth.width(of: glyph) == 1 ? glyph : " ", cellStyle)
    }
}
