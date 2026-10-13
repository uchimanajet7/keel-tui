import Darwin
import Foundation
import KeelTUI

/// A caller-owned input loop shared by two different kinds of scrolling content.
@MainActor
final class ScrollingExample {
    private var text = TerminalTextViewport(
        lines: (1 ... 24).flatMap { index in
            ["Paragraph \(index). This sentence has a natural ending.",
             "There is more to read. 日本語の文章と結合文字 e\u{301} also wrap at the available width.", ""]
        },
        scrollbar: TerminalScrollbar(gutter: .stable)
    )
    private var list = TerminalSelectableList(
        rows: (1 ... 60).map { "Item \($0)" },
        scrollbar: TerminalScrollbar(gutter: .stable)
    )
    private var focusesList = false
    private var decoder = TerminalKeyDecoder()
    private var originalMode = termios()
    private var readSource: DispatchSourceRead?
    private var resizeSource: DispatchSourceSignal?
    private var interruptSource: DispatchSourceSignal?
    private var textFrame = TerminalFrame(column: 0, line: 0, width: 0, height: 0)
    private var listFrame = TerminalFrame(column: 0, line: 0, width: 0, height: 0)
    private let lifecycle = TerminalLifecycle { output($0) }

    func start() {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1,
              tcgetattr(STDIN_FILENO, &originalMode) == 0 else {
            output("Run Scrolling in an interactive terminal.\n")
            return
        }
        var mode = originalMode
        mode.c_lflag &= ~tcflag_t(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &mode)
        lifecycle.enter()
        draw()

        let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        input.setEventHandler { [self] in
            let data = FileHandle.standardInput.availableData
            if data.isEmpty { stop() }
            for key in decoder.parse(data: data) { handle(key) }
            draw()
        }
        readSource = input
        input.resume()

        signal(SIGWINCH, SIG_IGN)
        let resize = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        resize.setEventHandler { [self] in draw() }
        resizeSource = resize
        resize.resume()

        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interrupt.setEventHandler { [self] in stop() }
        interruptSource = interrupt
        interrupt.resume()
        dispatchMain()
    }

    private func handle(_ key: TerminalKey) {
        switch key {
        case .character("q"), .ctrlC, .ctrlD:
            stop()
        case .tab:
            focusesList.toggle()
        case .character("u"):
            if focusesList { list.scroll(.pages(-1), in: listFrame) }
            else { text.scroll(.pages(-1), in: textFrame) }
        case .character("d"):
            if focusesList { list.scroll(.pages(1), in: listFrame) }
            else { text.scroll(.pages(1), in: textFrame) }
        case .character("g"):
            if focusesList { list.scroll(.start, in: listFrame) }
            else { text.scroll(.start, in: textFrame) }
        case .character("G"):
            if focusesList { list.scroll(.end, in: listFrame) }
            else { text.scroll(.end, in: textFrame) }
        default:
            if focusesList { list.handle(key, in: listFrame) }
            else { text.handle(key, in: textFrame) }
        }
    }

    private func draw() {
        var terminal = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &terminal) == 0 else { return }
        let size = TerminalSize(width: Int(terminal.ws_col), height: Int(terminal.ws_row))
        let bodyHeight = max(0, size.height - 2)
        let left = TerminalFrame(column: 0, line: 0, width: size.width / 2, height: bodyHeight)
        let right = TerminalFrame(column: left.width, line: 0, width: size.width - left.width, height: bodyHeight)
        textFrame = left.contentFrame()
        listFrame = right.contentFrame()
        var canvas = TerminalCanvas(size: size)
        canvas.drawBox(frame: left, title: "Text", focused: !focusesList)
        canvas.drawBox(frame: right, title: "List", focused: focusesList)
        text.draw(on: &canvas, frame: textFrame)
        list.draw(on: &canvas, frame: listFrame)
        canvas.draw("Tab: pane  Up/Down or j/k: move  PgUp/PgDn: page  q: quit",
                    column: 0, line: bodyHeight, maxWidth: size.width)
        canvas.draw("Home/End: endpoints  u/d: browse page  g/G: browse endpoints",
                    column: 0, line: bodyHeight + 1, maxWidth: size.width)
        output("\u{1B}[H" + canvas.snapshot().ansiText.replacingOccurrences(of: "\n", with: "\r\n"))
    }

    private func stop() -> Never {
        lifecycle.restore()
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalMode)
        exit(0)
    }
}

private func output(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

ScrollingExample().start()
