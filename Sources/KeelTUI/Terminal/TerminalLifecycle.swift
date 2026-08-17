import Foundation

public final class TerminalLifecycle {
    private let write: (String) -> Void
    public private(set) var isActive: Bool = false

    public init(write: @escaping (String) -> Void) {
        self.write = write
    }

    deinit {
        restore()
    }

    public func enter() {
        guard !isActive else { return }
        write(EscapeSequence.enableAlternateBuffer)
        write(EscapeSequence.clearScreen)
        write(EscapeSequence.hideCursor)
        isActive = true
    }

    public func restore() {
        guard isActive else { return }
        write(EscapeSequence.showCursor)
        write(EscapeSequence.disableAlternateBuffer)
        isActive = false
    }
}
