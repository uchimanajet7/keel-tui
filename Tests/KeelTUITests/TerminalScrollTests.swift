import XCTest
@testable import KeelTUI

final class TerminalScrollTests: XCTestCase {
    func testNormalizedRangesAndEndpointsAcrossContentAndViewportSizes() {
        for count in 0 ... 12 {
            for height in 0 ... 12 {
                for offset in [-1, 0, 1, 5, 12, Int.max] {
                    let state = TerminalScrollState(contentLength: count, viewportLength: height, offset: offset)
                    XCTAssertEqual(state.maximumOffset, max(0, count - height))
                    XCTAssertTrue((0 ... state.maximumOffset).contains(state.offset))
                    XCTAssertEqual(state.visibleRange.count, min(count, height))
                    XCTAssertLessThanOrEqual(state.visibleRange.upperBound, count)
                    XCTAssertEqual(state.hasContentBefore, state.visibleRange.lowerBound > 0)
                    XCTAssertEqual(state.hasContentAfter, state.visibleRange.upperBound < count)
                }
            }
        }
        XCTAssertEqual(TerminalScrollState(contentLength: -1, viewportLength: -2).visibleRange, 0 ..< 0)
    }

    func testMovementUsesClampedPositionAndActualViewportIncludingResize() {
        var state = TerminalScrollState(contentLength: 20, viewportLength: 7, offset: .max)
        state.move(.units(-1))
        XCTAssertEqual(state.offset, 12)
        state.move(.pages(-1))
        XCTAssertEqual(state.offset, 5)
        state.update(contentLength: 8, viewportLength: 5)
        XCTAssertEqual(state.offset, 3)
        state.move(.units(-1))
        XCTAssertEqual(state.visibleRange, 2 ..< 7)
        state.move(.end)
        XCTAssertEqual(state.visibleRange, 3 ..< 8)
        state.move(.start)
        XCTAssertEqual(state.visibleRange, 0 ..< 5)
        state.update(contentLength: 30, viewportLength: 9)
        state.move(.pages(1))
        XCTAssertEqual(state.offset, 9)
        state.update(contentLength: 30, viewportLength: 40)
        XCTAssertEqual(state.offset, 0)
    }

    func testSaturatingMovementAndProportionalGeometryAtIntegerLimits() {
        var state = TerminalScrollState(contentLength: .max, viewportLength: 3, offset: .max)
        state.move(.units(.max))
        XCTAssertEqual(state.offset, Int.max - 3)
        state.move(.units(.min))
        XCTAssertEqual(state.offset, 0)
        state.move(.pages(.max))
        XCTAssertEqual(state.offset, state.maximumOffset)
        let geometry = TerminalScrollbarGeometry(state: state, length: .max)
        XCTAssertEqual(geometry.thumbRange.upperBound, geometry.trackRange.upperBound)
        state.move(.pages(.min))
        XCTAssertEqual(state.offset, 0)
        state.update(contentLength: 10, viewportLength: 0)
        state.move(.pages(.max))
        state.move(.reveal(5 ..< 8))
        XCTAssertEqual(state.visibleRange, 0 ..< 0)
    }

    func testRevealClipsRangesAndAlignsOversizedContentAtItsStart() {
        var state = TerminalScrollState(contentLength: 40, viewportLength: 8)
        state.move(.reveal(10 ..< 13))
        XCTAssertEqual(state.visibleRange, 5 ..< 13)
        state.move(.reveal(7 ..< 9))
        XCTAssertEqual(state.offset, 5)
        state.move(.reveal(2 ..< 4))
        XCTAssertEqual(state.offset, 2)
        state.move(.reveal(10 ..< 30))
        XCTAssertEqual(state.offset, 10)
        state.move(.reveal(35 ..< Int.max))
        XCTAssertEqual(state.offset, 32)
        state.move(.reveal(-3 ..< 0))
        XCTAssertEqual(state.offset, 32)
    }

    func testInitialCompleteSentenceStillShowsContinuationAndEndpoints() {
        let frame = TerminalFrame(column: 1, line: 1, width: 28, height: 4)
        var viewport = TerminalTextViewport(lines: ["First complete sentence.", "Second complete sentence.",
                                                   "Third complete sentence.", "A natural ending.", "Still more below."])
        var canvas = TerminalCanvas(size: TerminalSize(width: 30, height: 6))
        let first = viewport.draw(on: &canvas, frame: frame)
        XCTAssertEqual(first.visibleLines.last, "A natural ending.")
        XCTAssertTrue(first.scroll.state.hasContentAfter)
        XCTAssertEqual(canvas.snapshot().cells[4][28].text, "↓")
        XCTAssertEqual(canvas.snapshot().cells[1][28].text, " ")
        viewport.handle(.end)
        let last = viewport.draw(on: &canvas, frame: frame)
        XCTAssertEqual(last.visibleLines.last, "Still more below.")
        XCTAssertEqual(canvas.snapshot().cells[1][28].text, "↑")
        XCTAssertEqual(canvas.snapshot().cells[4][28].text, " ")
        XCTAssertFalse(last.scroll.state.hasContentAfter)
    }

    func testStableGutterWrappingUnicodeAndNormalizedNextInput() {
        let frame = TerminalFrame(column: 0, line: 0, width: 7, height: 3)
        var viewport = TerminalTextViewport(lines: ["日本語e\u{301}文字"], scrollbar: TerminalScrollbar(gutter: .stable))
        let fitting = viewport.layout(in: frame)
        XCTAssertEqual(fitting.scroll.contentFrame.width, 6)
        XCTAssertEqual(fitting.wrappedLines, ["日本語", "e\u{301}文字"])
        viewport.lines += ["日本語e\u{301}文字", "Another ending."]
        let overflowing = viewport.layout(in: frame)
        XCTAssertEqual(overflowing.scroll.contentFrame, fitting.scroll.contentFrame)
        XCTAssertEqual(Array(overflowing.wrappedLines.prefix(2)), fitting.wrappedLines)
        viewport.scrollOffset = .max
        let last = viewport.layout(in: frame)
        XCTAssertEqual(viewport.scrollOffset, last.scroll.state.maximumOffset)
        viewport.handle(.arrowUp)
        XCTAssertEqual(viewport.scrollOffset, last.scroll.state.offset - 1)
        viewport.lines = ["Short"]
        viewport.handle(.pageUp)
        XCTAssertEqual(viewport.scrollOffset, 0)
    }

    func testAutomaticGutterRemeasuresAndHiddenStableGutterStillReservesWidth() {
        let frame = TerminalFrame(column: 0, line: 0, width: 6, height: 2)
        var viewport = TerminalTextViewport(lines: ["abcdef", "ghijkl", "mnopqr"])
        let layout = viewport.layout(in: frame)
        XCTAssertEqual(layout.scroll.contentFrame.width, 5)
        XCTAssertEqual(layout.wrappedLines, ["abcde", "f", "ghijk", "l", "mnopq", "r"])
        viewport.scrollbar = TerminalScrollbar(visibility: .hidden, gutter: .stable)
        var canvas = TerminalCanvas(size: TerminalSize(width: 6, height: 2))
        let hidden = viewport.draw(on: &canvas, frame: frame)
        XCTAssertEqual(hidden.scroll.contentFrame.width, 5)
        XCTAssertEqual(canvas.snapshot().cells[1][5].text, " ")
    }

    func testListSelectionAndBrowsingAreIndependentAndPagesUseViewport() {
        var list = TerminalSelectableList(rows: (0 ..< 30).map { "Row \($0)" })
        let frame = TerminalFrame(column: 0, line: 0, width: 12, height: 4)
        list.handle(.pageDown, in: frame)
        XCTAssertEqual(list.selectedIndex, 4)
        XCTAssertTrue(list.layout(in: frame).state.visibleRange.contains(4))
        list.scroll(.end, in: frame)
        XCTAssertEqual(list.selectedIndex, 4)
        XCTAssertEqual(list.visibleRows(height: 4).first?.index, 26)
        list.scroll(.pages(-1))
        XCTAssertEqual(list.scrollOffset, 22)
        list.revealSelection()
        XCTAssertEqual(list.scrollOffset, 4)
        list.rows = ["Only"]
        XCTAssertEqual(list.visibleRows(height: 4).map(\.index), [0])
        XCTAssertEqual(list.selectedIndex, 0)
        XCTAssertEqual(list.scrollOffset, 0)
        list.scrollOffset = .max
        list.handle(.arrowUp, in: frame)
        XCTAssertEqual(list.scrollOffset, 0)
    }

    func testTableKeepsHeaderFixedAndReturnsMovableBodyState() {
        let table = TerminalTable(columns: [TerminalTableColumn(header: "Header", width: 8)],
                                  rows: (0 ..< 10).map { TerminalTableRow(cells: [TerminalTableCell("Row \($0)")]) },
                                  selectedRowIndex: 0, selectionGutterWidth: 0,
                                  scrollbar: TerminalScrollbar(gutter: .stable))
        let frame = TerminalFrame(column: 1, line: 1, width: 10, height: 5)
        var canvas = TerminalCanvas(size: TerminalSize(width: 12, height: 7))
        let layout = table.draw(on: &canvas, frame: frame, rowOffset: .max)
        XCTAssertEqual(layout.state.viewportLength, 4)
        XCTAssertEqual(layout.state.visibleRange, 6 ..< 10)
        XCTAssertTrue(canvas.snapshot().line(1).contains("Header"))
        XCTAssertTrue(canvas.snapshot().line(2).contains("Row 6"))
        XCTAssertEqual(layout.scrollbarFrame.line, 2)
        var state = layout.state
        state.move(.pages(-1))
        XCTAssertEqual(state.offset, 2)
        XCTAssertEqual(table.layout(in: frame, maxRows: 2).state.viewportLength, 2)
        XCTAssertEqual(table.layout(in: TerminalFrame(column: 0, line: 0, width: 10, height: 1)).state.visibleRange, 0 ..< 0)
    }

    func testModalUsesFinalWrappedWidthAndBodyHeightForMovement() {
        var modal = TerminalModal(title: "Text", lines: Array(repeating: "日本語e\u{301} text.", count: 12),
                                  preferredWidth: 14, minimumWidth: 2, preferredHeight: 8,
                                  scrollOffset: .max, verticalPadding: 1, style: .unicodeContentTitle,
                                  focused: false, scrollbar: TerminalScrollbar(gutter: .stable))
        let area = TerminalFrame(column: 0, line: 0, width: 20, height: 12)
        let last = modal.layout(in: area)
        XCTAssertEqual(last.scroll.state.viewportLength, 3)
        XCTAssertEqual(last.contentFrame.width, 9)
        modal.scroll(.pages(-1), in: area)
        XCTAssertEqual(modal.scrollOffset, last.maximumScrollOffset - 3)
        modal.scroll(.start, in: area)
        var canvas = TerminalCanvas(size: TerminalSize(width: 20, height: 12))
        modal.draw(on: &canvas, in: area)
        let first = modal.layout(in: area)
        XCTAssertEqual(canvas.snapshot().cells[first.scroll.scrollbarFrame.maxLine][first.scroll.scrollbarFrame.column].text, "↓")
        XCTAssertEqual(first.visibleRange, 0 ..< 3)
        let empty = modal.layout(in: TerminalSize(width: 0, height: 0))
        XCTAssertEqual(empty.totalLineCount, modal.lines.count)
        XCTAssertTrue(empty.visibleRange.isEmpty)
    }

    func testSmallFramesNeverDrawOutsideTheirRegionOrInventVisibleContent() {
        for width in 0 ... 4 {
            for height in 0 ... 4 {
                let frame = TerminalFrame(column: 2, line: 2, width: width, height: height)
                var canvas = TerminalCanvas(size: TerminalSize(width: 8, height: 8))
                var viewport = TerminalTextViewport(lines: ["日本語", "e\u{301}", "More"], scrollbar: TerminalScrollbar(gutter: .stable))
                let layout = viewport.draw(on: &canvas, frame: frame)
                if width <= 1 || height == 0 { XCTAssertTrue(layout.scroll.state.visibleRange.isEmpty) }
                var list = TerminalSelectableList(rows: ["one", "two", "three"])
                _ = list.draw(on: &canvas, frame: frame)
                let table = TerminalTable(columns: [TerminalTableColumn(header: "H", width: 2)],
                                          rows: [TerminalTableRow(cells: [TerminalTableCell("R")])])
                _ = table.draw(on: &canvas, frame: frame)
                TerminalModal(title: "M", lines: ["one", "two", "three"]).draw(on: &canvas, in: frame)
                let snapshot = canvas.snapshot()
                for y in 0 ..< 8 {
                    for x in 0 ..< 8 where !frame.contains(column: x, line: y) {
                        XCTAssertEqual(snapshot.cells[y][x].text, " ", "\(width)x\(height), \(x),\(y)")
                    }
                }
            }
        }
    }

    func testScrollbarSmallHeightsStylesAndFitClearing() {
        let style = TerminalScrollbarStyle(trackStyle: TerminalStyle(isDim: true),
                                            thumbStyle: TerminalStyle(foreground: .yellow, isBold: true))
        let bar = TerminalScrollbar(gutter: .stable, style: style)
        for height in 1 ... 8 {
            let frame = TerminalFrame(column: 0, line: 0, width: 1, height: height)
            var canvas = TerminalCanvas(size: TerminalSize(width: 1, height: height))
            let middle = TerminalScrollState(contentLength: 30, viewportLength: 5, offset: 10)
            bar.draw(on: &canvas, frame: frame, state: middle)
            XCTAssertEqual(canvas.snapshot().cells[0][0].text, height == 1 ? "↕" : "↑")
            if height > 1 { XCTAssertEqual(canvas.snapshot().cells[height - 1][0].text, "↓") }
            if height >= 3 {
                let geometry = TerminalScrollbarGeometry(state: middle, length: height)
                XCTAssertEqual(canvas.snapshot().style(column: 0, line: geometry.thumbRange.lowerBound), style.thumbStyle)
            }
            bar.draw(on: &canvas, frame: frame, state: TerminalScrollState(contentLength: 5, viewportLength: 5))
            XCTAssertTrue(canvas.snapshot().lines.allSatisfy { $0 == " " })
        }
    }

    @MainActor
    func testDeclarativeScrollViewShowsOverflowWithoutFocusAndClipsWideChildren() throws {
        let node = Node(view: ScrollView(scrollbar: TerminalScrollbar(gutter: .stable)) {
            ForEach(0 ..< 12, id: \.self) { index in Text("Row \(index) is deliberately wide") }
        }.view)
        node.build()
        let control = try XCTUnwrap(node.control)
        control.layout(size: Size(width: 10, height: 5))
        control.layer.invalidated = nil
        control.layout(size: Size(width: 10, height: 5))
        XCTAssertNil(control.layer.invalidated, "An unchanged layout must not schedule another render")
        XCTAssertNil(control.firstSelectableElement)
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 4))?.char, "↓")
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 1))?.char, "█")
        control.scroll(to: Position(column: 0, line: 11))
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 0))?.char, "↑")
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 4))?.char, " ")
        control.layout(size: Size(width: 10, height: 20))
        XCTAssertEqual(control.layer.cell(at: Position(column: 0, line: 0))?.char, "R")
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 1))?.char, " ")
    }

    @MainActor
    func testDeclarativeFocusNavigationAndContentShrinkKeepTheViewportValid() throws {
        func content(_ count: Int) -> some View {
            ScrollView(scrollbar: TerminalScrollbar(gutter: .stable)) {
                ForEach(0 ..< count, id: \.self) { index in Button("Item \(index)") {} }
            }
        }
        let node = Node(view: content(12).view)
        node.build()
        let control = try XCTUnwrap(node.control)
        let window = Window()
        window.addControl(control)
        control.layout(size: Size(width: 10, height: 4))
        var selected = try XCTUnwrap(control.firstSelectableElement)
        for _ in 0 ..< 11 {
            selected = try XCTUnwrap(selected.selectableElement(below: 0))
            window.firstResponder = selected
            selected.becomeFirstResponder()
        }
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 0))?.char, "↑")
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 3))?.char, " ")
        XCTAssertEqual(control.layer.cell(at: Position(column: 0, line: 3))?.attributes.inverted, true)
        node.update(using: content(2).view)
        control.layout(size: Size(width: 10, height: 4))
        XCTAssertEqual(control.layer.cell(at: Position(column: 0, line: 0))?.char, "I")
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 0))?.char, " ")
        control.layout(size: Size(width: 0, height: 0))
        control.layout(size: Size(width: 10, height: 1))
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 0))?.char, "↓")
    }
}
