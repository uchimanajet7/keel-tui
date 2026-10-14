import Darwin
import Foundation
import KeelTUI

/// A caller-owned input loop comparing the same spacing across four components.
@MainActor
final class ScrollingExample {
    private var text = TerminalTextViewport(
        lines: (1 ... 24).flatMap { index in
            ["Paragraph \(index). This sentence has a natural ending.",
             "There is more to read. 日本語の文章と結合文字 e\u{301} also wrap at the available width.", ""]
        }
    )
    private var list = TerminalSelectableList(
        rows: (1 ... 60).map { "Item \($0). A deliberately long selectable row — 日本語 and e\u{301}." }
    )
    private var table = TerminalTable(
        columns: [TerminalTableColumn(header: "No.", width: 4),
                  TerminalTableColumn(header: "Description", width: 100)],
        rows: (1 ... 60).map { index in
            TerminalTableRow(cells: [TerminalTableCell("\(index)"),
                                     TerminalTableCell("A long selected table row — 日本語 and e\u{301} reach the content edge.")])
        },
        selectedRowIndex: 0
    )
    private var modal = TerminalModal(
        title: "Modal",
        lines: (1 ... 24).map { "Paragraph \($0). Long modal text wraps before scrolling. 日本語と結合文字 e\u{301}." },
        minimumWidth: 2
    )
    private var scrollbar = TerminalScrollbar(gutter: .stable, contentSpacing: 1)
    private var showsTableAndModal = false
    private var focusesRight = false
    private var tableOffset = 0
    private var decoder = TerminalKeyDecoder()
    private var originalMode = termios()
    private var readSource: DispatchSourceRead?
    private var resizeSource: DispatchSourceSignal?
    private var interruptSource: DispatchSourceSignal?
    private var textFrame = TerminalFrame(column: 0, line: 0, width: 0, height: 0)
    private var listFrame = TerminalFrame(column: 0, line: 0, width: 0, height: 0)
    private var tableFrame = TerminalFrame(column: 0, line: 0, width: 0, height: 0)
    private var modalArea = TerminalFrame(column: 0, line: 0, width: 0, height: 0)
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
            focusesRight.toggle()
        case .character("1"):
            showsTableAndModal = false
        case .character("2"):
            showsTableAndModal = true
        case .character("s"):
            scrollbar.contentSpacing = scrollbar.contentSpacing == 0 ? 1 : 0
            updateScrollbars()
        case .character("u"):
            browse(.pages(-1))
        case .character("d"):
            browse(.pages(1))
        case .character("g"):
            browse(.start)
        case .character("G"):
            browse(.end)
        default:
            if showsTableAndModal {
                guard let movement = movement(for: key) else { return }
                if focusesRight { modal.scroll(movement, in: modalArea) }
                else { moveTableSelection(movement) }
            } else if focusesRight {
                list.handle(key, in: listFrame)
            } else {
                text.handle(key, in: textFrame)
            }
        }
    }

    private func movement(for key: TerminalKey) -> TerminalScrollMovement? {
        switch key {
        case .arrowUp, .character("k"): return .units(-1)
        case .arrowDown, .character("j"): return .units(1)
        case .pageUp: return .pages(-1)
        case .pageDown: return .pages(1)
        case .home: return .start
        case .end: return .end
        default: return nil
        }
    }

    private func browse(_ movement: TerminalScrollMovement) {
        if showsTableAndModal {
            if focusesRight {
                modal.scroll(movement, in: modalArea)
            } else {
                var state = table.layout(in: tableFrame, rowOffset: tableOffset).state
                state.move(movement)
                tableOffset = state.offset
            }
        } else if focusesRight {
            list.scroll(movement, in: listFrame)
        } else {
            text.scroll(movement, in: textFrame)
        }
    }

    private func moveTableSelection(_ movement: TerminalScrollMovement) {
        var state = table.layout(in: tableFrame, rowOffset: tableOffset).state
        var selection = TerminalScrollState(contentLength: table.rows.count, viewportLength: 1,
                                             offset: table.selectedRowIndex ?? 0)
        if case .pages(let count) = movement {
            selection.move(.units(count * state.viewportLength))
        } else {
            selection.move(movement)
        }
        table.selectedRowIndex = selection.offset
        state.move(.reveal(selection.offset ..< selection.offset + 1))
        tableOffset = state.offset
    }

    private func draw() {
        var terminal = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &terminal) == 0 else { return }
        let size = TerminalSize(width: Int(terminal.ws_col), height: Int(terminal.ws_row))
        let bodyHeight = max(0, size.height - 3)
        let left = TerminalFrame(column: 0, line: 0, width: size.width / 2, height: bodyHeight)
        let right = TerminalFrame(column: left.width, line: 0, width: size.width - left.width, height: bodyHeight)
        textFrame = left.contentFrame()
        listFrame = right.contentFrame()
        tableFrame = left.contentFrame()
        modalArea = right
        updateScrollbars()
        var canvas = TerminalCanvas(size: size)
        if showsTableAndModal {
            canvas.drawBox(frame: left, title: "Table", focused: !focusesRight)
            let layout = table.draw(on: &canvas, frame: tableFrame, rowOffset: tableOffset)
            tableOffset = layout.state.offset
            modal.focused = focusesRight
            modal.draw(on: &canvas, in: modalArea)
        } else {
            canvas.drawBox(frame: left, title: "Text", focused: !focusesRight)
            canvas.drawBox(frame: right, title: "List", focused: focusesRight)
            text.draw(on: &canvas, frame: textFrame)
            list.draw(on: &canvas, frame: listFrame)
        }
        canvas.draw("Spacing: \(scrollbar.contentSpacing)  s: toggle 0/1  1: Text/List  2: Table/Modal",
                    column: 0, line: bodyHeight, maxWidth: size.width)
        canvas.draw("Tab: pane  Up/Down or j/k: move  PgUp/PgDn: page  q: quit",
                    column: 0, line: bodyHeight + 1, maxWidth: size.width)
        canvas.draw("Home/End: endpoints  u/d: browse page  g/G: browse endpoints",
                    column: 0, line: bodyHeight + 2, maxWidth: size.width)
        output("\u{1B}[H" + canvas.snapshot().ansiText.replacingOccurrences(of: "\n", with: "\r\n"))
    }

    private func updateScrollbars() {
        text.scrollbar = scrollbar
        list.scrollbar = scrollbar
        table.scrollbar = scrollbar
        modal.scrollbar = scrollbar
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
