import Foundation

public struct TerminalStyle: Equatable, Sendable {
    public var foreground: Color?
    public var background: Color?
    public var isBold: Bool
    public var isDim: Bool
    public var isReversed: Bool

    public init(
        foreground: Color? = nil,
        background: Color? = nil,
        isBold: Bool = false,
        isDim: Bool = false,
        isReversed: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isDim = isDim
        self.isReversed = isReversed
    }

    public static let plain = TerminalStyle()

    public func foreground(_ color: Color?) -> TerminalStyle {
        var style = self
        style.foreground = color
        return style
    }

    public func background(_ color: Color?) -> TerminalStyle {
        var style = self
        style.background = color
        return style
    }

    public func bold(_ isBold: Bool = true) -> TerminalStyle {
        var style = self
        style.isBold = isBold
        return style
    }

    public func dim(_ isDim: Bool = true) -> TerminalStyle {
        var style = self
        style.isDim = isDim
        return style
    }

    public func reversed(_ isReversed: Bool = true) -> TerminalStyle {
        var style = self
        style.isReversed = isReversed
        return style
    }

    var escapeSequence: String {
        guard self != .plain else { return "" }

        var output = ""
        if let foreground {
            output += foreground.foregroundEscapeSequence
        }
        if let background {
            output += background.backgroundEscapeSequence
        }
        if isBold {
            output += EscapeSequence.enableBold
        }
        if isDim {
            output += EscapeSequence.enableDim
        }
        if isReversed {
            output += EscapeSequence.enableInverted
        }
        return output
    }
}
