import Foundation

public struct TerminalSize: Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

public struct TerminalFrame: Equatable {
    public var column: Int
    public var line: Int
    public var width: Int
    public var height: Int

    public init(column: Int, line: Int, width: Int, height: Int) {
        self.column = column
        self.line = line
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var isEmpty: Bool {
        width == 0 || height == 0
    }

    public var minColumn: Int {
        column
    }

    public var minLine: Int {
        line
    }

    public var maxColumn: Int {
        column + width - 1
    }

    public var maxLine: Int {
        line + height - 1
    }

    public func insetBy(columns: Int, lines: Int) -> TerminalFrame {
        TerminalFrame(
            column: column + columns,
            line: line + lines,
            width: width - columns * 2,
            height: height - lines * 2
        )
    }

    public func sharedBorderFrame(sharesLeftBorder: Bool, sharesTopBorder: Bool) -> TerminalFrame {
        TerminalFrame(
            column: column - (sharesLeftBorder ? 1 : 0),
            line: line - (sharesTopBorder ? 1 : 0),
            width: width + (sharesLeftBorder ? 1 : 0),
            height: height + (sharesTopBorder ? 1 : 0)
        )
    }

    public func contentFrame(titlePlacement: TerminalBoxTitlePlacement = .border) -> TerminalFrame {
        let content = insetBy(columns: 1, lines: 1)
        switch titlePlacement {
        case .border:
            return content
        case .firstContentLine:
            return TerminalFrame(
                column: content.column,
                line: content.line + 1,
                width: content.width,
                height: content.height - 1
            )
        }
    }

    public func intersects(_ other: TerminalFrame) -> Bool {
        guard !isEmpty, !other.isEmpty else { return false }
        return minColumn <= other.maxColumn &&
            maxColumn >= other.minColumn &&
            minLine <= other.maxLine &&
            maxLine >= other.minLine
    }

    public func contains(column: Int, line: Int) -> Bool {
        guard !isEmpty else { return false }
        return column >= minColumn &&
            column <= maxColumn &&
            line >= minLine &&
            line <= maxLine
    }
}

public struct TerminalPaneID: Equatable, Hashable, RawRepresentable, ExpressibleByStringLiteral, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public struct TerminalPane: Equatable {
    public var id: TerminalPaneID
    public var title: String
    public var frame: TerminalFrame
    public var focused: Bool

    public init(id: TerminalPaneID, title: String, frame: TerminalFrame, focused: Bool) {
        self.id = id
        self.title = title
        self.frame = frame
        self.focused = focused
    }

    public var contentFrame: TerminalFrame {
        frame.insetBy(columns: 1, lines: 1)
    }

    public var sharedBorderFrame: TerminalFrame {
        frame.sharedBorderFrame(sharesLeftBorder: frame.column > 0, sharesTopBorder: frame.line > 0)
    }

    public func contentFrame(style: TerminalBoxStyle, sharedBorders: Bool = false) -> TerminalFrame {
        let borderFrame = sharedBorders ? sharedBorderFrame : frame
        return borderFrame.contentFrame(titlePlacement: style.titlePlacement)
    }
}

public struct TerminalPaneLayout: Equatable {
    public var size: TerminalSize
    public var panes: [TerminalPane]
    public var footerFrame: TerminalFrame

    public init(size: TerminalSize, panes: [TerminalPane], footerFrame: TerminalFrame) {
        self.size = size
        self.panes = panes
        self.footerFrame = footerFrame
    }

    public static func sidebarWithStackedDetail(
        size: TerminalSize,
        sidebar: TerminalPaneID,
        sidebarTitle: String,
        topDetail: TerminalPaneID,
        topDetailTitle: String,
        bottomDetail: TerminalPaneID,
        bottomDetailTitle: String,
        focusedPane: TerminalPaneID
    ) -> TerminalPaneLayout {
        let footerHeight = size.height > 0 ? 1 : 0
        let bodyHeight = max(0, size.height - footerHeight)
        let leftWidth = max(24, min(40, size.width / 3))
        let rightWidth = max(0, size.width - leftWidth)
        let eventsHeight = max(6, bodyHeight / 3)
        let logsHeight = max(0, bodyHeight - eventsHeight)

        let sidebarFrame = TerminalFrame(column: 0, line: 0, width: leftWidth, height: bodyHeight)
        let eventsFrame = TerminalFrame(column: leftWidth, line: 0, width: rightWidth, height: min(eventsHeight, bodyHeight))
        let logsFrame = TerminalFrame(column: leftWidth, line: eventsFrame.height, width: rightWidth, height: logsHeight)
        let footerFrame = TerminalFrame(column: 0, line: bodyHeight, width: size.width, height: footerHeight)

        return TerminalPaneLayout(
            size: size,
            panes: [
                TerminalPane(id: sidebar, title: sidebarTitle, frame: sidebarFrame, focused: focusedPane == sidebar),
                TerminalPane(id: topDetail, title: topDetailTitle, frame: eventsFrame, focused: focusedPane == topDetail),
                TerminalPane(id: bottomDetail, title: bottomDetailTitle, frame: logsFrame, focused: focusedPane == bottomDetail)
            ],
            footerFrame: footerFrame
        )
    }

    public func pane(_ id: TerminalPaneID) -> TerminalPane? {
        panes.first { $0.id == id }
    }

    public var hasOverlaps: Bool {
        let frames = panes.map(\.frame) + [footerFrame]
        for lhsIndex in frames.indices {
            for rhsIndex in frames.indices where rhsIndex > lhsIndex {
                if frames[lhsIndex].intersects(frames[rhsIndex]) {
                    return true
                }
            }
        }
        return false
    }
}
