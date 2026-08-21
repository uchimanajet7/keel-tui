import XCTest
@testable import KeelTUI

final class TerminalDashboardPrimitivesTests: XCTestCase {
    func testDefaultMultiPaneLayoutFits80x24And120x40() {
        for size in [TerminalSize(width: 80, height: 24), TerminalSize(width: 120, height: 40)] {
            let layout = DashboardFixtureState.layout(size: size, focusedPane: .services)
            let snapshot = DashboardFixtureState.fixture().render(size: size)

            XCTAssertFalse(layout.hasOverlaps)
            XCTAssertEqual(snapshot.lines.count, size.height)
            for index in snapshot.lines.indices {
                XCTAssertEqual(snapshot.displayWidthOfLine(index), size.width)
            }
            XCTAssertTrue(snapshot.text.contains("Services"))
            XCTAssertTrue(snapshot.text.contains("Events"))
            XCTAssertTrue(snapshot.text.contains("Logs"))
        }
    }

    func testKeyDecoderHandlesDashboardNavigationKeys() {
        var decoder = TerminalKeyDecoder()

        let keys = decoder.parse("qr\t\u{1B}[A\u{1B}[B\u{1B}[C\u{1B}[Djk\u{1B}[H\u{1B}[F\u{1B}[5~\u{1B}[6~")

        XCTAssertEqual(keys, [
            .character("q"),
            .character("r"),
            .tab,
            .arrowUp,
            .arrowDown,
            .arrowRight,
            .arrowLeft,
            .character("j"),
            .character("k"),
            .home,
            .end,
            .pageUp,
            .pageDown
        ])
    }

    func testDashboardHandlesRefreshAndInputWithoutBlockingStateUpdates() {
        var state = DashboardFixtureState.fixture()

        state.handle(.tab)
        XCTAssertEqual(state.focus.activeSection, .events)

        state.handle(.tab)
        XCTAssertEqual(state.focus.activeSection, .logs)

        state.handle(.character("j"))
        XCTAssertEqual(state.logs.scrollOffset, 1)

        state.handle(.character("r"))
        XCTAssertEqual(state.refreshCount, 1)
        XCTAssertTrue(state.events.lines.last?.contains("refresh 1") == true)
        XCTAssertTrue(state.logs.lines.last?.contains("without blocking input") == true)

        state.handle(.character("q"))
        XCTAssertFalse(state.isRunning)
    }

    func testListNavigationDoesNotWrapAtBoundaries() {
        var list = TerminalSelectableList(rows: ["one", "two"])

        list.handle(.arrowUp)
        XCTAssertEqual(list.selectedIndex, 0)

        list.handle(.end)
        XCTAssertEqual(list.selectedIndex, 1)

        list.handle(.arrowDown)
        XCTAssertEqual(list.selectedIndex, 1)
    }

    func testScrollableFakeLogSupportsAtLeast500Lines() {
        var state = DashboardFixtureState.fixture(logLineCount: 500)
        let logFrame = try! XCTUnwrap(DashboardFixtureState.layout(size: TerminalSize(width: 80, height: 24), focusedPane: .services).pane(.logs)?.contentFrame)

        XCTAssertGreaterThanOrEqual(state.logs.lines.count, 500)

        state.logs.scrollToBottom(height: logFrame.height)
        let visibleLines = state.logs.visibleLines(height: logFrame.height)

        XCTAssertEqual(visibleLines.last, "log 500  worker-日本 processed fake event")
    }

    func testResizeRedrawsCleanly() {
        let state = DashboardFixtureState.fixture()

        let compact = state.render(size: TerminalSize(width: 80, height: 24))
        let expanded = state.render(size: TerminalSize(width: 120, height: 40))

        XCTAssertEqual(compact.lines.count, 24)
        XCTAssertEqual(expanded.lines.count, 40)
        XCTAssertTrue(compact.text.contains("focus: services"))
        XCTAssertTrue(expanded.text.contains("focus: services"))
        XCTAssertEqual(compact.lines.map(TerminalDisplayWidth.width(of:)).max(), 80)
        XCTAssertEqual(expanded.lines.map(TerminalDisplayWidth.width(of:)).max(), 120)
    }

    func testTerminalLifecycleRestoresCursorAndAlternateBuffer() {
        var output = ""
        var lifecycle: TerminalLifecycle? = TerminalLifecycle { output += $0 }

        lifecycle?.enter()
        XCTAssertTrue(lifecycle?.isActive == true)
        lifecycle?.restore()
        XCTAssertTrue(lifecycle?.isActive == false)
        lifecycle = nil

        XCTAssertTrue(output.contains(EscapeSequence.enableAlternateBuffer))
        XCTAssertTrue(output.contains(EscapeSequence.hideCursor))
        XCTAssertTrue(output.contains(EscapeSequence.showCursor))
        XCTAssertTrue(output.contains(EscapeSequence.disableAlternateBuffer))
    }

    func testWideCharactersPreservePaneAlignment() {
        var state = DashboardFixtureState.fixture()
        state.services.rows = [
            "日本語-service   running",
            "worker-日本       running"
        ]

        let snapshot = state.render(size: TerminalSize(width: 80, height: 24))

        XCTAssertEqual(TerminalDisplayWidth.width(of: "日本語"), 6)
        XCTAssertTrue(snapshot.text.contains("日本語-service"))
        for index in snapshot.lines.indices {
            XCTAssertEqual(snapshot.displayWidthOfLine(index), 80)
        }
    }

    func testTerminalTableAlignsHeaderAndRowsWithSelectionGutter() {
        var canvas = TerminalCanvas(size: TerminalSize(width: 52, height: 4))
        let selectedStyle = TerminalStyle(isReversed: true)
        let table = TerminalTable(
            columns: [
                TerminalTableColumn(header: "image", width: 16, overflow: .truncateMiddle),
                TerminalTableColumn(header: "refs", width: 7),
                TerminalTableColumn(header: "descriptor", width: 14),
            ],
            rows: [
                TerminalTableRow(cells: [
                    TerminalTableCell("node:22-bookworm"),
                    TerminalTableCell("refs:0"),
                    TerminalTableCell("descriptor:6410B"),
                ]),
                TerminalTableRow(cells: [
                    TerminalTableCell("builder:0.12.0"),
                    TerminalTableCell("refs:1s"),
                    TerminalTableCell("descriptor:856B"),
                ]),
            ],
            selectedRowIndex: 1,
            selectedRowStyle: selectedStyle
        )

        table.draw(on: &canvas, frame: TerminalFrame(column: 0, line: 0, width: 52, height: 4))

        let snapshot = canvas.snapshot()
        let imageColumn = try! XCTUnwrap(snapshot.line(0).firstColumn(of: "image"))
        let refsColumn = try! XCTUnwrap(snapshot.line(0).firstColumn(of: "refs"))
        let descriptorColumn = try! XCTUnwrap(snapshot.line(0).firstColumn(of: "descriptor"))

        XCTAssertEqual(snapshot.line(1).firstColumn(of: "node:22-book"), imageColumn)
        XCTAssertEqual(snapshot.line(2).firstColumn(of: "builder:0.12.0"), imageColumn)
        XCTAssertEqual(snapshot.line(1).firstColumn(of: "refs:0"), refsColumn)
        XCTAssertEqual(snapshot.line(2).firstColumn(of: "refs:1s"), refsColumn)
        XCTAssertEqual(snapshot.line(1).firstColumn(of: "descriptor:641"), descriptorColumn)
        XCTAssertEqual(snapshot.line(2).firstColumn(of: "descriptor:856"), descriptorColumn)
        XCTAssertEqual(snapshot.line(2).firstColumn(of: "›"), 0)
        XCTAssertEqual(snapshot.style(column: imageColumn, line: 2), selectedStyle)
    }

    func testTerminalTableUsesDisplayWidthForWideCharacterCells() {
        var canvas = TerminalCanvas(size: TerminalSize(width: 34, height: 3))
        let table = TerminalTable(
            columns: [
                TerminalTableColumn(header: "image", width: 10, overflow: .truncateMiddle),
                TerminalTableColumn(header: "refs", width: 7),
            ],
            rows: [
                TerminalTableRow(cells: [
                    TerminalTableCell("日本語-image-reference"),
                    TerminalTableCell("refs:0"),
                ]),
            ]
        )

        table.draw(on: &canvas, frame: TerminalFrame(column: 0, line: 0, width: 34, height: 3))

        let snapshot = canvas.snapshot()
        let refsColumn = try! XCTUnwrap(snapshot.line(0).firstColumn(of: "refs"))

        XCTAssertTrue(snapshot.line(1).contains("…"))
        XCTAssertEqual(snapshot.cells[1][refsColumn].text, "r")
        XCTAssertEqual(snapshot.displayWidthOfLine(0), 34)
        XCTAssertEqual(snapshot.displayWidthOfLine(1), 34)
    }

    func testUnicodeContentTitleBoxStylePlacesTitlesInsideAndSupportsSharedBorders() {
        var canvas = TerminalCanvas(size: TerminalSize(width: 20, height: 6))
        let leftPane = TerminalPane(id: .services, title: "Left", frame: TerminalFrame(column: 0, line: 0, width: 10, height: 6), focused: true)
        let rightPane = TerminalPane(id: .events, title: "Right", frame: TerminalFrame(column: 10, line: 0, width: 10, height: 6), focused: false)

        canvas.drawBox(frame: leftPane.sharedBorderFrame, title: leftPane.title, focused: leftPane.focused, style: .unicodeContentTitle)
        canvas.drawBox(frame: rightPane.sharedBorderFrame, title: rightPane.title, focused: rightPane.focused, style: .unicodeContentTitle)
        let bodyFrame = leftPane.contentFrame(style: .unicodeContentTitle, sharedBorders: true)
        canvas.draw("body", column: bodyFrame.column, line: bodyFrame.line, maxWidth: bodyFrame.width)

        let snapshot = canvas.snapshot()

        XCTAssertEqual(snapshot.line(0), "┏━━━━━━━━┌─────────┐")
        XCTAssertTrue(snapshot.line(1).contains("┃● Left  │  Right  │"))
        XCTAssertTrue(snapshot.line(2).contains("┃body    │         │"))
    }

    func testTerminalCanvasKeepsPlainSnapshotTextSeparateFromANSIStyleOutput() {
        var canvas = TerminalCanvas(size: TerminalSize(width: 12, height: 2))
        let style = TerminalStyle(foreground: .green, isBold: true)

        canvas.draw("OK", column: 0, line: 0, style: style)

        let snapshot = canvas.snapshot()

        XCTAssertEqual(snapshot.line(0), "OK          ")
        XCTAssertEqual(snapshot.style(column: 0, line: 0), style)
        XCTAssertEqual(snapshot.style(column: 2, line: 0), .plain)
        XCTAssertFalse(snapshot.text.contains("\u{1B}"))
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.setForegroundColor(.green)))
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.enableBold))
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.resetAttributes))
    }

    func testTerminalBoxStyleCanStyleBordersAndTitlesWithoutChangingPlainText() {
        var canvas = TerminalCanvas(size: TerminalSize(width: 16, height: 5))
        let boxStyle = TerminalBoxStyle(
            normal: .init(
                topLeft: "┌",
                topRight: "┐",
                bottomLeft: "└",
                bottomRight: "┘",
                horizontal: "─",
                vertical: "│"
            ),
            focused: .init(
                topLeft: "┏",
                topRight: "┓",
                bottomLeft: "┗",
                bottomRight: "┛",
                horizontal: "━",
                vertical: "┃"
            ),
            titlePrefix: "",
            focusedTitlePrefix: "● ",
            titlePlacement: .firstContentLine,
            normalStyle: TerminalStyle(foreground: .gray),
            focusedStyle: TerminalStyle(foreground: .cyan, isBold: true),
            titleStyle: TerminalStyle(foreground: .white),
            focusedTitleStyle: TerminalStyle(foreground: .brightCyan, isBold: true)
        )

        canvas.drawBox(frame: TerminalFrame(column: 0, line: 0, width: 16, height: 5), title: "Pane", focused: true, style: boxStyle)

        let snapshot = canvas.snapshot()

        XCTAssertEqual(snapshot.line(0), "┏━━━━━━━━━━━━━━┓")
        XCTAssertEqual(snapshot.style(column: 0, line: 0), boxStyle.focusedStyle)
        XCTAssertEqual(snapshot.style(column: 1, line: 1), boxStyle.focusedTitleStyle)
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.setForegroundColor(.brightCyan)))
        XCTAssertFalse(snapshot.text.contains("\u{1B}"))
    }

    func testTerminalModalClearsAndDrawsCenteredOverlay() {
        var canvas = TerminalCanvas(size: TerminalSize(width: 40, height: 12))
        for line in 0 ..< canvas.size.height {
            canvas.draw(String(repeating: "x", count: canvas.size.width), column: 0, line: line)
        }

        let modal = TerminalModal(
            title: "Confirm",
            lines: ["Primary line", "Secondary line", "Tertiary line"],
            preferredWidth: 24,
            minimumWidth: 24
        )
        let frame = modal.frame(in: canvas.size)

        modal.draw(on: &canvas)

        let snapshot = canvas.snapshot()
        let contentLine = String(snapshot.line(frame.line + 1).dropFirst(frame.column).prefix(frame.width))

        XCTAssertEqual(frame, TerminalFrame(column: 8, line: 3, width: 24, height: 5))
        XCTAssertTrue(snapshot.line(frame.line).contains("Confirm"))
        XCTAssertTrue(contentLine.contains("Primary line"))
        XCTAssertFalse(contentLine.contains("x"))
        XCTAssertFalse(snapshot.line(frame.line + 1).contains("x"))
    }

    func testTerminalModalCanStyleIndividualLinesWithoutChangingText() {
        var canvas = TerminalCanvas(size: TerminalSize(width: 44, height: 10))
        let dangerStyle = TerminalStyle(foreground: .red, isBold: true)
        let safeStyle = TerminalStyle(isDim: true)
        let modal = TerminalModal(
            title: "Confirm",
            styledLines: [
                TerminalModalLine(text: "Danger action", style: dangerStyle),
                TerminalModalLine(text: "Safe actions", style: safeStyle),
            ],
            preferredWidth: 24
        )
        let frame = modal.frame(in: canvas.size)

        modal.draw(on: &canvas)

        let snapshot = canvas.snapshot()
        let dangerLine = try! XCTUnwrap(snapshot.lines.firstIndex { $0.contains("Danger action") })
        let safeLine = try! XCTUnwrap(snapshot.lines.firstIndex { $0.contains("Safe actions") })
        let dangerColumn = try! XCTUnwrap(snapshot.line(dangerLine).firstColumn(of: "Danger action"))
        let safeColumn = try! XCTUnwrap(snapshot.line(safeLine).firstColumn(of: "Safe actions"))

        XCTAssertTrue(snapshot.text.contains("Danger action"))
        XCTAssertTrue(snapshot.text.contains("Safe actions"))
        XCTAssertGreaterThanOrEqual(dangerColumn, frame.column)
        XCTAssertGreaterThanOrEqual(safeColumn, frame.column)
        XCTAssertEqual(snapshot.style(column: dangerColumn, line: dangerLine), dangerStyle)
        XCTAssertEqual(snapshot.style(column: safeColumn, line: safeLine), safeStyle)
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.setForegroundColor(.red)))
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.enableDim))
    }

    func testTerminalStatusBarCanStyleShortcutsAndLabelsWithoutChangingText() {
        var canvas = TerminalCanvas(size: TerminalSize(width: 30, height: 1))
        let status = TerminalStatusBar(
            items: [
                TerminalStatusBarItem(shortcut: "q", label: "Quit"),
                TerminalStatusBarItem(shortcut: "r", label: "Refresh")
            ],
            shortcutStyle: TerminalStyle(foreground: .yellow, isBold: true),
            labelStyle: TerminalStyle(foreground: .white),
            backgroundStyle: TerminalStyle(background: .black)
        )

        status.draw(on: &canvas, frame: TerminalFrame(column: 0, line: 0, width: 30, height: 1))

        let snapshot = canvas.snapshot()

        XCTAssertEqual(snapshot.line(0), status.text(width: 30))
        XCTAssertEqual(snapshot.style(column: 1, line: 0), status.shortcutStyle)
        XCTAssertEqual(snapshot.style(column: 3, line: 0), status.labelStyle)
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.setForegroundColor(.yellow)))
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.setBackgroundColor(.black)))
        XCTAssertFalse(snapshot.text.contains("\u{1B}"))
    }

    func testTerminalStatusBarCanStyleIndividualItemsWithoutChangingText() {
        var canvas = TerminalCanvas(size: TerminalSize(width: 34, height: 1))
        let dangerStyle = TerminalStyle(foreground: .red, isBold: true)
        let mutedStyle = TerminalStyle(isDim: true)
        let status = TerminalStatusBar(
            items: [
                TerminalStatusBarItem(shortcut: "y", label: "Force kill", shortcutStyle: dangerStyle, labelStyle: dangerStyle),
                TerminalStatusBarItem(shortcut: "n", label: "Cancel", shortcutStyle: mutedStyle, labelStyle: .plain),
            ],
            shortcutStyle: TerminalStyle(foreground: .cyan),
            labelStyle: .plain
        )

        status.draw(on: &canvas, frame: TerminalFrame(column: 0, line: 0, width: 34, height: 1))

        let snapshot = canvas.snapshot()

        XCTAssertEqual(snapshot.line(0), status.text(width: 34))
        XCTAssertEqual(snapshot.style(column: 1, line: 0), dangerStyle)
        XCTAssertEqual(snapshot.style(column: 3, line: 0), dangerStyle)
        XCTAssertEqual(snapshot.style(column: 15, line: 0), mutedStyle)
        XCTAssertEqual(snapshot.style(column: 17, line: 0), .plain)
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.setForegroundColor(.red)))
        XCTAssertTrue(snapshot.ansiText.contains(EscapeSequence.enableDim))
    }

    func testTerminalStatusBarCompactsAndOmitsWholeItemsByRetentionPriority() {
        let highShortcutStyle = TerminalStyle(foreground: .red, isBold: true)
        let highLabelStyle = TerminalStyle(foreground: .brightRed)
        let lowShortcutStyle = TerminalStyle(foreground: .cyan)
        let lowLabelStyle = TerminalStyle(isDim: true)
        let status = TerminalStatusBar(items: [
            TerminalStatusBarItem(
                shortcut: "a",
                label: "Alpha",
                compactLabel: "A",
                retentionPriority: 10,
                shortcutStyle: highShortcutStyle,
                labelStyle: highLabelStyle
            ),
            TerminalStatusBarItem(
                shortcut: "b",
                label: "Beta",
                compactLabel: "B",
                shortcutStyle: lowShortcutStyle,
                labelStyle: lowLabelStyle
            ),
            TerminalStatusBarItem(
                shortcut: "c",
                label: "Gamma",
                compactLabel: "G"
            ),
            TerminalStatusBarItem(shortcut: "h", label: "Hidden", isVisible: false),
            TerminalStatusBarItem(shortcut: "d", label: "Disabled", isEnabled: false),
        ])

        XCTAssertEqual(status.text(width: 26), " a Alpha  b Beta  c Gamma ")
        XCTAssertEqual(
            status.text(width: 25),
            TerminalDisplayWidth.padRight(" a Alpha  b Beta  c G ", toWidth: 25)
        )
        XCTAssertEqual(
            status.text(width: 15),
            " a A  b B  c G "
        )
        XCTAssertEqual(
            status.text(width: 14),
            TerminalDisplayWidth.padRight(" a A  b B ", toWidth: 14)
        )
        XCTAssertEqual(
            status.text(width: 9),
            TerminalDisplayWidth.padRight(" a A ", toWidth: 9)
        )
        XCTAssertEqual(status.text(width: 4), String(repeating: " ", count: 4))
        XCTAssertEqual(status.text(width: 1), " ")
        XCTAssertEqual(status.text(width: 0), "")

        for width in [26, 25, 15, 14, 9, 4, 1, 0] {
            var canvas = TerminalCanvas(size: TerminalSize(width: width, height: 1))
            status.draw(
                on: &canvas,
                frame: TerminalFrame(column: 0, line: 0, width: width, height: 1)
            )

            XCTAssertEqual(canvas.snapshot().line(0), status.text(width: width))
        }

        var compactCanvas = TerminalCanvas(size: TerminalSize(width: 14, height: 1))
        status.draw(
            on: &compactCanvas,
            frame: TerminalFrame(column: 0, line: 0, width: 14, height: 1)
        )
        let compactSnapshot = compactCanvas.snapshot()

        XCTAssertEqual(compactSnapshot.style(column: 1, line: 0), highShortcutStyle)
        XCTAssertEqual(compactSnapshot.style(column: 3, line: 0), highLabelStyle)
        XCTAssertEqual(compactSnapshot.style(column: 6, line: 0), lowShortcutStyle)
        XCTAssertEqual(compactSnapshot.style(column: 8, line: 0), lowLabelStyle)
        XCTAssertFalse(compactSnapshot.text.contains("c"))
        XCTAssertFalse(compactSnapshot.text.contains("G"))
    }

    func testTerminalStatusBarMeasuresWideItemsWithoutDrawingFragments() {
        let status = TerminalStatusBar(items: [
            TerminalStatusBarItem(shortcut: "日", label: "本")
        ])

        XCTAssertEqual(status.text(width: 7), " 日 本 ")
        XCTAssertEqual(TerminalDisplayWidth.width(of: status.text(width: 7)), 7)
        XCTAssertEqual(status.text(width: 6), String(repeating: " ", count: 6))

        var canvas = TerminalCanvas(size: TerminalSize(width: 6, height: 1))
        status.draw(on: &canvas, frame: TerminalFrame(column: 0, line: 0, width: 6, height: 1))

        XCTAssertEqual(canvas.snapshot().line(0), status.text(width: 6))
        XCTAssertFalse(canvas.snapshot().text.contains("日"))
        XCTAssertFalse(canvas.snapshot().text.contains("本"))
    }

    func testTerminalStatusBarIncludesSeparatorsOnlyWhenBothItemsFit() {
        let status = TerminalStatusBar(items: [
            TerminalStatusBarItem(shortcut: "q", label: "A"),
            TerminalStatusBarItem(shortcut: "w", label: "B"),
        ])

        XCTAssertEqual(status.text(width: 10), " q A  w B ")
        XCTAssertEqual(
            status.text(width: 9),
            TerminalDisplayWidth.padRight(" q A ", toWidth: 9)
        )
        XCTAssertEqual(status.text(width: 5), " q A ")
        XCTAssertEqual(status.text(width: 4), String(repeating: " ", count: 4))
        XCTAssertFalse(status.text(width: 9).contains("  w"))
        XCTAssertFalse(status.text(width: 9).contains("w"))
        XCTAssertFalse(status.text(width: 9).contains("B"))
    }

    func testTerminalTextLayoutWrapsWordsTokensNewlinesAndBoundaryWidths() {
        XCTAssertEqual(
            TerminalTextLayout.wrap("hello world", width: 5).map(\.text),
            ["hello", "world"]
        )
        XCTAssertEqual(
            TerminalTextLayout.wrap("abcdefgh", width: 3).map(\.text),
            ["abc", "def", "gh"]
        )
        XCTAssertEqual(
            TerminalTextLayout.wrap("one\n\ntwo\n", width: 10).map(\.text),
            ["one", "", "two", ""]
        )
        XCTAssertEqual(
            TerminalTextLayout.wrap("日本語", width: 4).map(\.text),
            ["日本", "語"]
        )
        XCTAssertEqual(
            TerminalTextLayout.wrap("A👩‍💻B", width: 2).map(\.text),
            ["A", "👩‍💻", "B"]
        )
        XCTAssertEqual(
            TerminalTextLayout.wrap("e\u{301}x", width: 1).map(\.text),
            ["e\u{301}", "x"]
        )
        XCTAssertEqual(TerminalTextLayout.wrap("text", width: 0).map(\.text), [""])
        XCTAssertEqual(TerminalTextLayout.wrap("日", width: 1).map(\.text), ["日"])
        XCTAssertEqual(TerminalDisplayWidth.width(of: "👩‍💻"), 2)
        XCTAssertEqual(TerminalDisplayWidth.width(of: "e\u{301}"), 1)
        XCTAssertEqual(TerminalTextLayout.wrap("e\u{301}", width: 1)[0].text.count, 1)
    }

    func testTerminalTextLayoutPreservesStylesAndContinuationIndent() {
        let primaryStyle = TerminalStyle(foreground: .red)
        let accentStyle = TerminalStyle(foreground: .cyan, isBold: true)
        let indentStyle = TerminalStyle(isDim: true)
        let input = TerminalModalLine(
            segments: [
                TerminalStyledTextSegment("ab ", style: primaryStyle),
                TerminalStyledTextSegment("日本👩‍💻e\u{301}", style: accentStyle),
            ],
            continuationIndent: "↳ ",
            continuationIndentStyle: indentStyle
        )

        let wrapped = TerminalTextLayout.wrap([input], width: 6)

        XCTAssertEqual(wrapped.map(\.text), ["ab", "↳ 日本", "↳ 👩‍💻e\u{301}"])
        XCTAssertEqual(wrapped[0].segments, [
            TerminalStyledTextSegment("ab", style: primaryStyle)
        ])
        XCTAssertEqual(wrapped[1].segments, [
            TerminalStyledTextSegment("↳ ", style: indentStyle),
            TerminalStyledTextSegment("日本", style: accentStyle),
        ])
        XCTAssertEqual(wrapped[2].segments, [
            TerminalStyledTextSegment("↳ ", style: indentStyle),
            TerminalStyledTextSegment("👩‍💻e\u{301}", style: accentStyle),
        ])

        let oversizedIndent = TerminalModalLine(text: "ab", continuationIndent: "----")
        XCTAssertEqual(
            TerminalTextLayout.wrap([oversizedIndent], width: 1).map(\.text),
            ["a", "b"]
        )
    }

    func testTerminalModalWrapsBeforeSizingAndNormalizesItsViewport() {
        let firstModal = TerminalModal(
            title: "Help",
            lines: ["alpha beta gamma delta"],
            preferredWidth: 12,
            minimumWidth: 12,
            maximumHeight: 5
        )
        let lastModal = TerminalModal(
            title: "Help",
            lines: ["alpha beta gamma delta"],
            preferredWidth: 12,
            minimumWidth: 12,
            maximumHeight: 5,
            scrollOffset: 99
        )
        let size = TerminalSize(width: 20, height: 10)
        let first = firstModal.layout(in: size)
        let last = lastModal.layout(in: size)

        XCTAssertEqual(first.frame, TerminalFrame(column: 4, line: 2, width: 12, height: 5))
        XCTAssertEqual(first.naturalHeight, 6)
        XCTAssertEqual(first.contentFrame.width, 8)
        XCTAssertEqual(first.contentFrame.height, 3)
        XCTAssertEqual(first.totalLineCount, 4)
        XCTAssertEqual(first.maximumScrollOffset, 1)
        XCTAssertEqual(first.scrollOffset, 0)
        XCTAssertEqual(first.visibleRange, 0 ..< 3)
        XCTAssertEqual(first.visibleLines.map(\.text), ["alpha", "beta", "gamma"])
        XCTAssertEqual(last.scrollOffset, 1)
        XCTAssertEqual(last.visibleRange, 1 ..< 4)
        XCTAssertEqual(last.visibleLines.map(\.text), ["beta", "gamma", "delta"])

        var canvas = TerminalCanvas(size: size)
        for line in 0 ..< size.height {
            canvas.draw(String(repeating: "x", count: size.width), column: 0, line: line)
        }
        lastModal.draw(on: &canvas)
        let snapshot = canvas.snapshot()
        let firstContentRow = String(
            snapshot.line(last.contentFrame.line)
                .dropFirst(last.frame.column)
                .prefix(last.frame.width)
        )

        XCTAssertTrue(snapshot.line(last.frame.line).contains("Help"))
        XCTAssertTrue(snapshot.line(last.frame.maxLine).contains("┗"))
        XCTAssertTrue(firstContentRow.contains("beta"))
        XCTAssertFalse(firstContentRow.contains("x"))
        XCTAssertEqual(snapshot.line(0), String(repeating: "x", count: size.width))
        XCTAssertEqual(lastModal.scrollOffset, 99)

        lastModal.draw(on: &canvas)
        XCTAssertEqual(canvas.snapshot(), snapshot)
    }

    func testTerminalModalHeightBoundsStayInsideTheAvailableArea() {
        let modal = TerminalModal(
            title: "Bounds",
            lines: ["one"],
            preferredWidth: 30,
            preferredHeight: 8,
            minimumHeight: 4,
            maximumHeight: 6
        )
        let area = TerminalFrame(column: 3, line: 2, width: 10, height: 3)
        let layout = modal.layout(in: area)

        XCTAssertEqual(layout.frame, area)
        XCTAssertEqual(layout.naturalHeight, 3)
        XCTAssertEqual(layout.frame.height, 3)
        XCTAssertGreaterThanOrEqual(layout.frame.minColumn, area.minColumn)
        XCTAssertLessThanOrEqual(layout.frame.maxColumn, area.maxColumn)
        XCTAssertGreaterThanOrEqual(layout.frame.minLine, area.minLine)
        XCTAssertLessThanOrEqual(layout.frame.maxLine, area.maxLine)

        let roomySize = TerminalSize(width: 30, height: 12)
        let minimumLayout = TerminalModal(
            title: "Minimum",
            lines: ["one"],
            preferredWidth: 12,
            minimumWidth: 12,
            minimumHeight: 5,
            maximumHeight: 8
        ).layout(in: roomySize)
        let preferredLayout = TerminalModal(
            title: "Preferred",
            lines: ["one"],
            preferredWidth: 12,
            minimumWidth: 12,
            preferredHeight: 6,
            minimumHeight: 3,
            maximumHeight: 8
        ).layout(in: roomySize)
        let emptyLayout = modal.layout(
            in: TerminalFrame(column: 3, line: 2, width: -1, height: -1)
        )

        XCTAssertEqual(minimumLayout.naturalHeight, 3)
        XCTAssertEqual(minimumLayout.frame.height, 5)
        XCTAssertEqual(preferredLayout.naturalHeight, 3)
        XCTAssertEqual(preferredLayout.frame.height, 6)
        XCTAssertEqual(emptyLayout.frame.width, 0)
        XCTAssertEqual(emptyLayout.frame.height, 0)
        XCTAssertGreaterThanOrEqual(emptyLayout.contentFrame.width, 0)
        XCTAssertGreaterThanOrEqual(emptyLayout.contentFrame.height, 0)
    }

    func testTerminalModalViewportReachesFirstMiddleAndLastRows() {
        let lines = (0 ..< 6).map { "row \($0)" }
        func layout(offset: Int) -> TerminalModalLayout {
            TerminalModal(
                title: "Rows",
                lines: lines,
                preferredWidth: 12,
                minimumWidth: 12,
                maximumHeight: 5,
                scrollOffset: offset
            ).layout(in: TerminalSize(width: 20, height: 10))
        }

        let first = layout(offset: 0)
        let middle = layout(offset: 2)
        let last = layout(offset: .max)
        let reached = Set(
            (first.visibleLines + middle.visibleLines + last.visibleLines).map(\.text)
        )

        XCTAssertEqual(first.visibleRange, 0 ..< 3)
        XCTAssertEqual(middle.visibleRange, 2 ..< 5)
        XCTAssertEqual(last.visibleRange, 3 ..< 6)
        XCTAssertEqual(last.maximumScrollOffset, 3)
        XCTAssertEqual(last.scrollOffset, 3)
        XCTAssertEqual(reached, Set(lines))
    }

    func testKeyBindingPresentationFeedsStatusAndGroupedHelpFromOneDescriptorSet() {
        let shortcutStyle = TerminalStyle(foreground: .yellow, isBold: true)
        let descriptionStyle = TerminalStyle(foreground: .white)
        let bindings = [
            TerminalKeyBindingPresentation(
                id: "quit",
                shortcut: "q",
                description: "Quit",
                compactDescription: "Close",
                groupID: "general",
                groupTitle: "General",
                retentionPriority: 10,
                shortcutStyle: shortcutStyle,
                descriptionStyle: descriptionStyle
            ),
            TerminalKeyBindingPresentation(
                id: "refresh",
                shortcut: "r",
                description: "Refresh",
                groupID: "general",
                groupTitle: "General",
                isEnabled: false,
                shortcutStyle: TerminalStyle(foreground: .cyan),
                descriptionStyle: TerminalStyle(isDim: true)
            ),
            TerminalKeyBindingPresentation(
                id: "move",
                shortcut: "↑↓",
                description: "Move selection",
                groupID: "navigation",
                groupTitle: "Navigation"
            ),
            TerminalKeyBindingPresentation(
                id: "hidden",
                shortcut: "x",
                description: "Hidden",
                groupID: "general",
                groupTitle: "General",
                isVisible: false
            ),
        ]

        let includingDisabled = bindings.statusBarItems(disabledVisibility: .include)
        let excludingDisabled = bindings.statusBarItems(disabledVisibility: .exclude)
        let help = TerminalBindingHelp.lines(
            from: bindings,
            width: 24,
            disabledVisibility: .include
        )
        let enabledHelp = TerminalBindingHelp.lines(
            from: bindings,
            width: 24,
            disabledVisibility: .exclude
        )

        XCTAssertEqual(includingDisabled.map(\.label), ["Quit", "Refresh", "Move selection"])
        XCTAssertEqual(excludingDisabled.map(\.label), ["Quit", "Move selection"])
        XCTAssertEqual(includingDisabled[0].compactLabel, "Close")
        XCTAssertEqual(includingDisabled[0].retentionPriority, 10)
        XCTAssertEqual(includingDisabled[0].shortcutStyle, shortcutStyle)
        XCTAssertEqual(includingDisabled[0].labelStyle, descriptionStyle)
        XCTAssertEqual(includingDisabled[2].shortcut, "↑↓")
        XCTAssertEqual(
            help.map(\.text),
            ["General", "q   Quit", "r   Refresh", "Navigation", "↑↓  Move selection"]
        )
        XCTAssertEqual(
            enabledHelp.map(\.text),
            ["General", "q   Quit", "Navigation", "↑↓  Move selection"]
        )
        XCTAssertEqual(help[1].segments.first?.style, shortcutStyle)
        XCTAssertEqual(help[1].segments.last?.style, descriptionStyle)
        XCTAssertFalse(help.map(\.text).contains { $0.contains("Hidden") })

        var focusSpecificBindings = bindings
        focusSpecificBindings[0].isVisible = false
        focusSpecificBindings[2].isEnabled = false
        XCTAssertEqual(
            focusSpecificBindings
                .statusBarItems(disabledVisibility: .exclude)
                .map(\.label),
            []
        )
        XCTAssertEqual(
            focusSpecificBindings
                .statusBarItems(disabledVisibility: .include)
                .map(\.label),
            ["Refresh", "Move selection"]
        )

        let wrappedHelp = TerminalBindingHelp.lines(
            from: [
                TerminalKeyBindingPresentation(
                    id: "open",
                    shortcut: "enter",
                    description: "Open selected resource",
                    groupID: "actions",
                    groupTitle: ""
                )
            ],
            width: 16,
            disabledVisibility: .exclude
        )

        XCTAssertEqual(
            wrappedHelp.map(\.text),
            ["enter  Open", "       selected", "       resource"]
        )
        XCTAssertTrue(wrappedHelp.allSatisfy {
            TerminalDisplayWidth.width(of: $0.text) <= 16
        })
    }
}

private extension TerminalPaneID {
    static let services: TerminalPaneID = "services"
    static let events: TerminalPaneID = "events"
    static let logs: TerminalPaneID = "logs"
}

private extension String {
    func firstColumn(of needle: String) -> Int? {
        guard let range = range(of: needle) else { return nil }
        return distance(from: startIndex, to: range.lowerBound)
    }
}

private struct DashboardFixtureState: Equatable {
    var services: TerminalSelectableList
    var events: TerminalTextViewport
    var logs: TerminalTextViewport
    var focus: TerminalFocusCoordinator
    var isRunning: Bool
    var refreshCount: Int

    static func fixture(logLineCount: Int = 500) -> DashboardFixtureState {
        let services = TerminalSelectableList(rows: [
            "web        healthy   127.0.0.1:8080",
            "worker-日本 active    queue:default",
            "database   paused    volume:data",
            "cache      active    memory:256MiB"
        ])
        let events = TerminalTextViewport(lines: [
            "ready: fake dashboard inventory loaded",
            "watch: input remains responsive during refresh"
        ])
        let logs = TerminalTextViewport(lines: (1 ... max(1, logLineCount)).map {
            String(format: "log %03d  worker-日本 processed fake event", $0)
        })
        let focus = TerminalFocusCoordinator(sections: [.services, .events, .logs], activeSection: .services)
        return DashboardFixtureState(services: services, events: events, logs: logs, focus: focus, isRunning: true, refreshCount: 0)
    }

    static func layout(size: TerminalSize, focusedPane: TerminalPaneID) -> TerminalPaneLayout {
        TerminalPaneLayout.sidebarWithStackedDetail(
            size: size,
            sidebar: .services,
            sidebarTitle: "Services",
            topDetail: .events,
            topDetailTitle: "Events",
            bottomDetail: .logs,
            bottomDetailTitle: "Logs",
            focusedPane: focusedPane
        )
    }

    mutating func handle(_ key: TerminalKey) {
        switch key {
        case .character(let character) where character == "q":
            isRunning = false
        case .character(let character) where character == "r":
            refresh()
        case .tab:
            _ = focus.handle(key)
        default:
            handleFocusedPane(key)
        }
    }

    mutating func refresh() {
        refreshCount += 1
        let selectedIndex = services.selectedIndex
        if services.rows.isEmpty {
            services.rows = ["web        healthy   127.0.0.1:8080"]
        } else {
            services.rows[0] = "web        healthy   refreshed:\(refreshCount)"
        }
        services.selectedIndex = min(selectedIndex, max(0, services.rows.count - 1))
        events.append("refresh \(refreshCount): service list and events updated")
        logs.append(String(format: "log %03d  refresh completed without blocking input", logs.lines.count + 1))
    }

    func render(size: TerminalSize) -> TerminalSnapshot {
        let layout = Self.layout(size: size, focusedPane: focus.activeSection)
        var canvas = TerminalCanvas(size: size)

        for pane in layout.panes {
            canvas.drawBox(frame: pane.frame, title: pane.title, focused: pane.focused)
        }

        drawServices(on: &canvas, in: layout.pane(.services)?.contentFrame)
        drawEvents(on: &canvas, in: layout.pane(.events)?.contentFrame)
        drawLogs(on: &canvas, in: layout.pane(.logs)?.contentFrame)
        drawFooter(on: &canvas, in: layout.footerFrame)

        return canvas.snapshot()
    }

    private mutating func handleFocusedPane(_ key: TerminalKey) {
        switch focus.activeSection {
        case .services:
            services.handle(key)
        case .events:
            events.handle(key)
        case .logs:
            logs.handle(key)
        default:
            break
        }
    }

    private func drawServices(on canvas: inout TerminalCanvas, in frame: TerminalFrame?) {
        guard let frame else { return }
        let rows = services.visibleRows(height: frame.height)
        for (rowOffset, row) in rows.enumerated() {
            let cursor = row.isSelected ? "›" : " "
            canvas.draw(
                "\(cursor) \(row.text)",
                column: frame.column,
                line: frame.line + rowOffset,
                maxWidth: frame.width
            )
        }
    }

    private func drawEvents(on canvas: inout TerminalCanvas, in frame: TerminalFrame?) {
        guard let frame else { return }
        let lines = events.visibleLines(height: frame.height)
        for (lineOffset, line) in lines.enumerated() {
            canvas.draw(
                line,
                column: frame.column,
                line: frame.line + lineOffset,
                maxWidth: frame.width
            )
        }
    }

    private func drawLogs(on canvas: inout TerminalCanvas, in frame: TerminalFrame?) {
        guard let frame else { return }
        let lines = logs.visibleLines(height: frame.height)
        for (lineOffset, line) in lines.enumerated() {
            canvas.draw(
                line,
                column: frame.column,
                line: frame.line + lineOffset,
                maxWidth: frame.width
            )
        }
    }

    private func drawFooter(on canvas: inout TerminalCanvas, in frame: TerminalFrame) {
        let status = TerminalStatusBar(items: [
            TerminalStatusBarItem(shortcut: "tab", label: "focus"),
            TerminalStatusBarItem(shortcut: "↑↓/j/k", label: "move"),
            TerminalStatusBarItem(shortcut: "r", label: "refresh"),
            TerminalStatusBarItem(shortcut: "q", label: "quit")
        ])
        status.draw(on: &canvas, frame: frame)

        let runningText = isRunning ? "running" : "stopped"
        let suffix = " focus: \(focus.activeSection.rawValue) | \(runningText) "
        canvas.draw(suffix, column: max(0, frame.maxColumn - TerminalDisplayWidth.width(of: suffix) + 1), line: frame.line, maxWidth: TerminalDisplayWidth.width(of: suffix))
    }
}
