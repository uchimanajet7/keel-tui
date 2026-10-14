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

    func testSpacingReservationPoliciesAndExtremeWidths() {
        for gutter in [TerminalScrollbarGutter.stable, .automatic] {
            for visibility in [TerminalScrollbarVisibility.whenNeeded, .hidden] {
                for spacing in [Int.min, -1, 0, 1, 3, Int.max] {
                    let bar = TerminalScrollbar(visibility: visibility, gutter: gutter, contentSpacing: spacing)
                    for count in [0, 2, 8] {
                        for width in 0 ... 10 {
                            let frame = TerminalFrame(column: 2, line: 1, width: width, height: 4)
                            let layout = bar.layout(in: frame, contentLength: count, offset: .max)
                            let reserved = gutter == .stable || (visibility == .whenNeeded && count > 4)
                            XCTAssertEqual(layout.scrollbarFrame.width, reserved && width > 0 ? 1 : 0)
                            XCTAssertEqual(layout.contentFrame.width + layout.spacingFrame.width + layout.scrollbarFrame.width, width)
                            XCTAssertEqual(layout.contentFrame.column + layout.contentFrame.width, layout.spacingFrame.column)
                            XCTAssertEqual(layout.spacingFrame.column + layout.spacingFrame.width, layout.scrollbarFrame.column)
                            XCTAssertFalse(layout.contentFrame.intersects(layout.spacingFrame))
                            XCTAssertFalse(layout.spacingFrame.intersects(layout.scrollbarFrame))
                            XCTAssertFalse(layout.contentFrame.intersects(layout.scrollbarFrame))
                            if !reserved || spacing <= 0 || width <= 2 { XCTAssertEqual(layout.spacingFrame.width, 0) }
                            if reserved && width == 2 { XCTAssertEqual(layout.contentFrame.width, 1) }
                            if reserved && width == 1 { XCTAssertEqual(layout.contentFrame.width, 0) }
                            if width == 0 || layout.contentFrame.width == 0 { XCTAssertTrue(layout.state.visibleRange.isEmpty) }
                            if reserved && width > 2 && spacing == .max { XCTAssertEqual(layout.contentFrame.width, 1) }
                        }
                    }
                }
            }
        }
        var bar = TerminalScrollbar(gutter: .stable, contentSpacing: 1)
        bar.contentSpacing = .min
        let huge = TerminalFrame(column: 0, line: 0, width: .max, height: 1)
        XCTAssertEqual(bar.layout(in: huge, contentLength: 1).contentFrame.width, Int.max - 1)
        bar.contentSpacing = .max
        let layout = bar.layout(in: huge, contentLength: 1)
        XCTAssertEqual(layout.contentFrame.width, 1)
        XCTAssertEqual(layout.spacingFrame.width, Int.max - 2)
        XCTAssertEqual(layout.scrollbarFrame.column, Int.max - 1)
    }

    func testAutomaticSpacingMeasuresUnreservedWidthBeforeDecidingToWrapAgain() {
        let frame = TerminalFrame(column: 0, line: 0, width: 10, height: 3)
        for visibility in [TerminalScrollbarVisibility.whenNeeded, .hidden] {
            for gutter in [TerminalScrollbarGutter.automatic, .stable] {
                for count in [0, 3, 5] {
                    var widths: [Int] = []
                    let bar = TerminalScrollbar(visibility: visibility, gutter: gutter, contentSpacing: 2)
                    let layout = bar.layout(in: frame) { width in
                        widths.append(width)
                        return count
                    }
                    let expected = gutter == .stable ? [7]
                        : visibility == .whenNeeded && count > 3 ? [10, 7] : [10]
                    XCTAssertEqual(widths, expected)
                    XCTAssertEqual(layout.contentFrame.width, expected.last)
                }
            }
        }
        var text = TerminalTextViewport(lines: ["abcdefghij", "klmnopqrst", "uvwxyzABCD"],
                                        scrollbar: TerminalScrollbar(contentSpacing: 2))
        XCTAssertEqual(text.layout(in: frame).wrappedLines.count, 3)
        XCTAssertEqual(text.layout(in: frame).scroll.spacingFrame.width, 0)
        text.lines.append("EFGHIJKLMN")
        let overflow = text.layout(in: frame)
        XCTAssertEqual(overflow.scroll.contentFrame.width, 7)
        XCTAssertEqual(overflow.wrappedLines, ["abcdefg", "hij", "klmnopq", "rst", "uvwxyzA", "BCD", "EFGHIJK", "LMN"])
    }

    func testSpacedTextUsesFinalUnicodeRowsForRangeEndpointsAndResize() {
        var text = TerminalTextViewport(lines: ["日本語e\u{301}文字"],
                                        scrollbar: TerminalScrollbar(gutter: .stable, contentSpacing: 1))
        var frame = TerminalFrame(column: 1, line: 1, width: 7, height: 2)
        var canvas = TerminalCanvas(size: TerminalSize(width: 12, height: 5))
        let first = text.draw(on: &canvas, frame: frame)
        XCTAssertEqual(first.wrappedLines, ["日本", "語e\u{301}文", "字"])
        XCTAssertEqual(first.scroll.state.visibleRange, 0 ..< 2)
        XCTAssertEqual(canvas.snapshot().cells[2][7].text, "↓")
        XCTAssertEqual(canvas.snapshot().cells[2][3].text, "e\u{301}")
        text.scroll(.end, in: frame)
        let last = text.draw(on: &canvas, frame: frame)
        XCTAssertEqual(last.scroll.state.visibleRange, 1 ..< 3)
        XCTAssertEqual(canvas.snapshot().cells[1][7].text, "↑")
        XCTAssertEqual(canvas.snapshot().cells[2][7].text, " ")
        XCTAssertEqual(canvas.snapshot().cells[1][6].text, " ")
        frame.width = 10
        XCTAssertEqual(text.layout(in: frame).scroll.state.offset, 0)
        text.lines = []
        XCTAssertTrue(text.draw(on: &canvas, frame: frame).visibleLines.isEmpty)
        XCTAssertTrue(canvas.snapshot().lines.allSatisfy { $0.allSatisfy { $0 == " " } })
    }

    func testLayoutDrawingClearsSpacingWithNormalBackgroundAndLegacyDrawStaysInBar() {
        let size = TerminalSize(width: 12, height: 6)
        let frame = TerminalFrame(column: 2, line: 1, width: 8, height: 4)
        let bar = TerminalScrollbar(gutter: .stable, contentSpacing: 2)
        let layout = bar.layout(in: frame, contentLength: 10)
        let selected = TerminalStyle(background: .red, isBold: true, isReversed: true)
        var canvas = TerminalCanvas(size: size)
        canvas.clear(frame: TerminalFrame(column: 0, line: 0, width: 12, height: 6), style: selected)
        let before = canvas.snapshot()
        bar.draw(on: &canvas, frame: layout.scrollbarFrame, state: layout.state)
        for y in 0 ..< size.height {
            for x in 0 ..< size.width where !layout.scrollbarFrame.contains(column: x, line: y) {
                XCTAssertEqual(canvas.snapshot().cells[y][x], before.cells[y][x])
            }
        }
        bar.draw(on: &canvas, layout: layout, background: .blue)
        for y in 0 ..< size.height {
            for x in 0 ..< size.width {
                let cell = canvas.snapshot().cells[y][x]
                if layout.spacingFrame.contains(column: x, line: y) {
                    XCTAssertEqual(cell.text, " ")
                    XCTAssertEqual(cell.style, TerminalStyle(background: .blue))
                } else if !layout.scrollbarFrame.contains(column: x, line: y) {
                    XCTAssertEqual(cell, before.cells[y][x])
                }
            }
        }
        for outside in [TerminalFrame(column: 20, line: 0, width: 5, height: 3),
                        TerminalFrame(column: 0, line: 20, width: 5, height: 3)] {
            let snapshot = canvas.snapshot()
            bar.draw(on: &canvas, layout: bar.layout(in: outside, contentLength: 10))
            XCTAssertEqual(canvas.snapshot(), snapshot)
        }
    }

    func testListSpacingSeparatesSelectionAndRedrawsAfterSettingsAndContentChanges() {
        let size = TerminalSize(width: 12, height: 5)
        let frame = TerminalFrame(column: 1, line: 1, width: 10, height: 3)
        let normal = TerminalStyle(background: .blue)
        let selected = TerminalStyle(background: .red, isReversed: true)
        var list = TerminalSelectableList(rows: Array(repeating: "日本語e\u{301} very long selected row", count: 10),
                                           scrollbar: TerminalScrollbar(gutter: .stable))
        var canvas = TerminalCanvas(size: size)
        for spacing in [0, 1, 3, 0, 2] {
            list.scrollbar.contentSpacing = spacing
            list.handle(.arrowDown, in: frame)
            let layout = list.draw(on: &canvas, frame: frame, style: normal, selectedStyle: selected, background: .blue)
            var freshCanvas = TerminalCanvas(size: size)
            list.draw(on: &freshCanvas, frame: frame, style: normal, selectedStyle: selected, background: .blue)
            XCTAssertEqual(canvas.snapshot(), freshCanvas.snapshot())
            for line in frame.line ... frame.maxLine {
                for column in layout.spacingFrame.column ..< layout.scrollbarFrame.column {
                    XCTAssertEqual(canvas.snapshot().cells[line][column].text, " ")
                    XCTAssertEqual(canvas.snapshot().style(column: column, line: line), normal)
                }
            }
            let selectedLine = frame.line + list.selectedIndex - layout.state.offset
            XCTAssertEqual(canvas.snapshot().style(column: frame.column, line: selectedLine), selected)
        }
        list.scrollbar.gutter = .automatic
        list.rows = ["Only"]
        list.draw(on: &canvas, frame: frame, style: normal, selectedStyle: selected, background: .blue)
        var fresh = TerminalCanvas(size: size)
        list.draw(on: &fresh, frame: frame, style: normal, selectedStyle: selected, background: .blue)
        XCTAssertEqual(canvas.snapshot(), fresh.snapshot())
        XCTAssertEqual(canvas.snapshot().style(column: frame.maxColumn, line: frame.maxLine), normal)
        XCTAssertEqual(list.selectedIndex, 0)
        XCTAssertEqual(list.scrollOffset, 0)
        list.rows = []
        list.draw(on: &canvas, frame: frame, style: normal, background: .blue)
        XCTAssertEqual(canvas.snapshot().cells[1][1].text, " ")
        XCTAssertEqual(canvas.snapshot().style(column: 1, line: 1), normal)
    }

    func testSurfaceBackgroundIsSeparateFromExistingTextAndSelectionStyles() {
        let size = TerminalSize(width: 8, height: 3)
        let frame = TerminalFrame(column: 0, line: 0, width: 8, height: 3)
        let emphasis = TerminalStyle(background: .red, isReversed: true)
        var canvas = TerminalCanvas(size: size)
        var text = TerminalTextViewport(lines: ["X", "Y", "Z", "W"])
        text.draw(on: &canvas, frame: frame, style: emphasis)
        XCTAssertEqual(canvas.snapshot().style(column: 0, line: 0), emphasis)
        XCTAssertEqual(canvas.snapshot().style(column: 1, line: 0), .plain)
        XCTAssertEqual(canvas.snapshot().style(column: 7, line: 2), .plain)
        text.scrollbar.contentSpacing = 1
        text.draw(on: &canvas, frame: frame, style: emphasis, background: .blue)
        XCTAssertEqual(canvas.snapshot().style(column: 0, line: 0), emphasis)
        XCTAssertEqual(canvas.snapshot().style(column: 1, line: 0), TerminalStyle(background: .blue))
        XCTAssertEqual(canvas.snapshot().cells[0][6].text, " ")
        XCTAssertEqual(canvas.snapshot().style(column: 6, line: 0), TerminalStyle(background: .blue))

        var list = TerminalSelectableList(rows: ["X", "Y", "Z", "W"])
        list.draw(on: &canvas, frame: frame, style: TerminalStyle(background: .red))
        XCTAssertEqual(canvas.snapshot().style(column: 0, line: 0), TerminalStyle(isReversed: true))
        XCTAssertEqual(canvas.snapshot().style(column: 0, line: 1), TerminalStyle(background: .red))
        XCTAssertEqual(canvas.snapshot().style(column: 1, line: 0), .plain)

        let modal = TerminalModal(title: "M", lines: ["X", "Y", "Z"], preferredWidth: 10,
                                  minimumWidth: 2, preferredHeight: 4, contentStyle: emphasis)
        canvas = TerminalCanvas(size: TerminalSize(width: 12, height: 6))
        modal.draw(on: &canvas)
        let layout = modal.layout(in: canvas.size)
        XCTAssertEqual(canvas.snapshot().style(column: layout.contentFrame.column, line: layout.contentFrame.line), emphasis)
        XCTAssertEqual(canvas.snapshot().style(column: layout.contentFrame.column - 1, line: layout.contentFrame.line), .plain)
        XCTAssertEqual(canvas.snapshot().style(column: layout.scroll.scrollbarFrame.column, line: layout.contentFrame.line), .plain)
    }

    func testTableSpacingClipsFixedHeaderAndSelectedRowsAtTheSameWidth() {
        var table = TerminalTable(
            columns: [TerminalTableColumn(header: "Long header", width: 30)],
            rows: (0 ..< 8).map { TerminalTableRow(cells: [TerminalTableCell("Long selected row \($0)")]) },
            selectedRowIndex: 7, selectionGutterWidth: 0,
            scrollbar: TerminalScrollbar(gutter: .stable, contentSpacing: 2)
        )
        let frame = TerminalFrame(column: 1, line: 1, width: 10, height: 4)
        var canvas = TerminalCanvas(size: TerminalSize(width: 12, height: 6))
        let layout = table.draw(on: &canvas, frame: frame, rowOffset: .max, background: .blue)
        XCTAssertEqual(layout.contentFrame.width, 7)
        XCTAssertEqual(layout.state.contentLength, 8)
        XCTAssertEqual(layout.state.visibleRange, 5 ..< 8)
        XCTAssertEqual(canvas.snapshot().cells[1][7].text, "e")
        XCTAssertEqual(canvas.snapshot().style(column: 7, line: 4)?.isReversed, true)
        for y in frame.line ... frame.maxLine {
            for x in 8 ... 9 {
                XCTAssertEqual(canvas.snapshot().cells[y][x].text, " ")
                XCTAssertEqual(canvas.snapshot().style(column: x, line: y), TerminalStyle(background: .blue))
            }
        }
        table.rows = []
        table.scrollbar.gutter = .automatic
        let empty = table.draw(on: &canvas, frame: frame, rowOffset: .max, background: .blue)
        XCTAssertEqual(empty.contentFrame.width, 10)
        XCTAssertTrue(empty.state.visibleRange.isEmpty)
        XCTAssertEqual(canvas.snapshot().cells[4][10].text, " ")
        XCTAssertEqual(canvas.snapshot().style(column: 7, line: 4)?.isReversed, false)
    }

    func testModalSpacingUsesCommonWidthForNaturalAndExplicitSizes() {
        let area = TerminalFrame(column: 1, line: 1, width: 30, height: 12)
        var modal = TerminalModal(title: "M", lines: ["abcdefghij"], minimumWidth: 2,
                                  scrollbar: TerminalScrollbar(gutter: .stable, contentSpacing: 2))
        let natural = modal.layout(in: area)
        XCTAssertEqual(natural.frame.width, 17)
        XCTAssertEqual(natural.contentFrame.width, 10)
        XCTAssertEqual(natural.wrappedLines.map(\.text), ["abcdefghij"])
        modal.preferredWidth = 12
        modal.preferredHeight = 5
        let fixed = modal.layout(in: area)
        XCTAssertEqual(fixed.frame.width, 12)
        XCTAssertEqual(fixed.contentFrame.width, 5)
        XCTAssertEqual(fixed.wrappedLines.map(\.text), ["abcde", "fghij"])
        modal.scrollbar.contentSpacing = .max
        XCTAssertEqual(modal.layout(in: area).frame.width, 12)
        XCTAssertEqual(modal.layout(in: area).contentFrame.width, 1)
        modal.preferredWidth = nil
        modal.maximumWidth = 20
        XCTAssertEqual(modal.layout(in: area).frame.width, 20)
        modal.minimumWidth = 40
        modal.minimumHeight = 20
        modal.maximumHeight = 7
        XCTAssertEqual(modal.layout(in: area).frame.width, 20)
        XCTAssertEqual(modal.layout(in: area).frame.height, 7)
        XCTAssertEqual(modal.layout(in: TerminalSize(width: 9, height: 4)).frame.width, 9)
        XCTAssertEqual(modal.layout(in: TerminalSize(width: 9, height: 4)).frame.height, 4)
    }

    func testModalAutomaticSpacingRemeasuresAndClearsOnShrinkWithoutFocusChanges() {
        let area = TerminalFrame(column: 0, line: 0, width: 18, height: 10)
        var modal = TerminalModal(title: "M", lines: Array(repeating: "日本語e\u{301}文字", count: 8),
                                  preferredWidth: 13, minimumWidth: 2, preferredHeight: 7,
                                  verticalPadding: 1, style: .unicodeContentTitle,
                                  contentStyle: TerminalStyle(background: .blue, isReversed: true),
                                  scrollbar: TerminalScrollbar(contentSpacing: 2))
        var canvas = TerminalCanvas(size: TerminalSize(width: 18, height: 10))
        let layout = modal.layout(in: area)
        XCTAssertEqual(layout.contentFrame.width, 6)
        XCTAssertEqual(layout.contentFrame.height, 2)
        XCTAssertEqual(layout.wrappedLines, TerminalTextLayout.wrap(modal.styledLines, width: 6))
        modal.scroll(.end, in: area)
        modal.draw(on: &canvas, in: area, background: .blue)
        let last = modal.layout(in: area)
        XCTAssertEqual(last.visibleRange.upperBound, last.totalLineCount)
        XCTAssertEqual(canvas.snapshot().cells[last.scroll.scrollbarFrame.line][last.scroll.scrollbarFrame.column].text, "↑")
        for y in last.scroll.spacingFrame.line ... last.scroll.spacingFrame.maxLine {
            for x in last.scroll.spacingFrame.column ... last.scroll.spacingFrame.maxColumn {
                XCTAssertEqual(canvas.snapshot().cells[y][x].text, " ")
                XCTAssertEqual(canvas.snapshot().style(column: x, line: y), TerminalStyle(background: .blue))
            }
        }
        modal.focused = false
        XCTAssertEqual(modal.layout(in: area).scroll, last.scroll)
        modal.lines = ["Short"]
        modal.draw(on: &canvas, in: area, background: .blue)
        let fit = modal.layout(in: area)
        XCTAssertEqual(fit.scroll.spacingFrame.width, 0)
        XCTAssertEqual(fit.contentFrame.width, 9)
        var fresh = TerminalCanvas(size: canvas.size)
        modal.draw(on: &fresh, in: area, background: .blue)
        XCTAssertEqual(canvas.snapshot(), fresh.snapshot())
    }

    func testModalAutomaticSpacingPreservesExistingNaturalOuterWidth() {
        let area = TerminalFrame(column: 0, line: 0, width: 40, height: 12)
        for (spacing, contentWidth, rowCount) in [(Int.min, 9, 20), (0, 9, 20), (1, 8, 20), (Int.max, 1, 100)] {
            var modal = TerminalModal(title: "M", lines: Array(repeating: "abcdefghij", count: 10),
                                      minimumWidth: 2, maximumHeight: 5,
                                      scrollbar: TerminalScrollbar(contentSpacing: spacing))
            let layout = modal.layout(in: area)
            XCTAssertEqual(layout.frame.width, 14)
            XCTAssertEqual(layout.frame.height, 5)
            XCTAssertEqual(layout.contentFrame.width, contentWidth)
            XCTAssertEqual(layout.totalLineCount, rowCount)
            XCTAssertEqual(layout.visibleRange, 0 ..< 3)
            modal.scrollbar.visibility = .hidden
            let hidden = modal.layout(in: area)
            XCTAssertEqual(hidden.frame.width, 14)
            XCTAssertEqual(hidden.contentFrame.width, 10)
            XCTAssertEqual(hidden.scroll.spacingFrame.width, 0)
            XCTAssertEqual(hidden.totalLineCount, 10)
        }
    }

    func testAllCanvasComponentsHandleSpacingInTinyFramesWithoutWritingOutside() {
        for width in 0 ... 4 {
            for height in 0 ... 4 {
                for spacing in [1, Int.max] {
                    let frame = TerminalFrame(column: 2, line: 2, width: width, height: height)
                    let bar = TerminalScrollbar(gutter: .stable, contentSpacing: spacing)
                    var canvas = TerminalCanvas(size: TerminalSize(width: 9, height: 9))
                    let full = TerminalFrame(column: 0, line: 0, width: 9, height: 9)
                    canvas.clear(frame: full, style: TerminalStyle(background: .yellow))
                    let before = canvas.snapshot()
                    var text = TerminalTextViewport(lines: ["日本語", "e\u{301}", "more"], scrollbar: bar)
                    let textLayout = text.draw(on: &canvas, frame: frame)
                    if width <= 1 || height == 0 { XCTAssertTrue(textLayout.visibleLines.isEmpty) }
                    if width == 2 && height > 0 { XCTAssertEqual(canvas.snapshot().cells[2][2].text, " ") }
                    var list = TerminalSelectableList(rows: ["日本語", "e\u{301}", "more"], scrollbar: bar)
                    let listLayout = list.draw(on: &canvas, frame: frame)
                    let table = TerminalTable(columns: [TerminalTableColumn(header: "日本", width: 3)],
                                              rows: [TerminalTableRow(cells: [TerminalTableCell("語e\u{301}")])], scrollbar: bar)
                    let tableLayout = table.draw(on: &canvas, frame: frame)
                    let modal = TerminalModal(title: "M", lines: ["日本語", "e\u{301}", "more"], scrollbar: bar)
                    modal.draw(on: &canvas, in: frame)
                    if width <= 1 || height == 0 {
                        XCTAssertTrue(listLayout.state.visibleRange.isEmpty)
                        XCTAssertTrue(tableLayout.state.visibleRange.isEmpty)
                        XCTAssertTrue(modal.layout(in: frame).visibleRange.isEmpty)
                    }
                    for y in 0 ..< 9 {
                        for x in 0 ..< 9 where !frame.contains(column: x, line: y) {
                            XCTAssertEqual(canvas.snapshot().cells[y][x], before.cells[y][x], "\(width)x\(height)")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testZeroSpacingPreservesAllFiveComponentLayoutsAndRendering() throws {
        let size = TerminalSize(width: 12, height: 5)
        let frame = TerminalFrame(column: 0, line: 0, width: 12, height: 5)
        for gutter in [TerminalScrollbarGutter.stable, .automatic] {
            let original = TerminalScrollbar(gutter: gutter)
            let explicit = TerminalScrollbar(gutter: gutter, contentSpacing: 0)
            var canvases: [TerminalSnapshot] = []
            for bar in [original, explicit] {
                var canvas = TerminalCanvas(size: size)
                var text = TerminalTextViewport(lines: Array(repeating: "日本語e\u{301} long text", count: 8), scrollbar: bar)
                text.draw(on: &canvas, frame: frame)
                canvases.append(canvas.snapshot())
                var list = TerminalSelectableList(rows: Array(repeating: "Long selected item", count: 8), scrollbar: bar)
                list.draw(on: &canvas, frame: frame)
                canvases.append(canvas.snapshot())
                TerminalTable(columns: [TerminalTableColumn(header: "Header", width: 20)],
                              rows: (0 ..< 8).map { TerminalTableRow(cells: [TerminalTableCell("Row \($0)")]) },
                              scrollbar: bar).draw(on: &canvas, frame: frame)
                canvases.append(canvas.snapshot())
                TerminalModal(title: "M", lines: Array(repeating: "long modal text", count: 8),
                              minimumWidth: 2, scrollbar: bar).draw(on: &canvas, in: frame)
                canvases.append(canvas.snapshot())
            }
            XCTAssertEqual(Array(canvases.prefix(4)), Array(canvases.suffix(4)))
            let nodes = [original, explicit].map { bar in
                Node(view: ScrollView(scrollbar: bar) {
                    ForEach(0 ..< 8, id: \.self) { _ in Text("Long declarative text") }
                }.view)
            }
            for node in nodes {
                node.build()
                node.control?.layout(size: Size(width: 12, height: 5))
            }
            for y in 0 ..< 5 {
                for x in 0 ..< 12 {
                    let position = Position(column: Extended(x), line: Extended(y))
                    XCTAssertEqual(nodes[0].control?.layer.cell(at: position), nodes[1].control?.layer.cell(at: position))
                }
            }
        }
    }

    @MainActor
    func testDeclarativeSpacingClipsSelectionPreservesBackgroundAndRespondsToChanges() throws {
        func content(count: Int = 12, spacing: Int, gutter: TerminalScrollbarGutter = .stable,
                     visibility: TerminalScrollbarVisibility = .whenNeeded) -> some View {
            ScrollView(scrollbar: TerminalScrollbar(visibility: visibility, gutter: gutter, contentSpacing: spacing)) {
                ForEach(0 ..< count, id: \.self) { index in Button("Item \(index) has a long label") {} }
            }.background(.blue)
        }
        let node = Node(view: content(spacing: 1).view)
        node.build()
        let control = node.control(at: 0)
        let scrollControl = control.children[0]
        let window = Window()
        window.addControl(control)
        control.layout(size: Size(width: 10, height: 4))
        let first = try XCTUnwrap(control.firstSelectableElement)
        first.becomeFirstResponder()
        XCTAssertEqual(scrollControl.children[0].layer.frame.size.width, 8)
        XCTAssertEqual(scrollControl.children[0].children[0].layer.frame.size.width, 8)
        XCTAssertEqual(control.layer.cell(at: Position(column: 7, line: 0))?.attributes.inverted, true)
        for line in 0 ..< 4 {
            let gap = try XCTUnwrap(control.layer.cell(at: Position(column: 8, line: Extended(line))))
            XCTAssertEqual(gap.char, " ")
            XCTAssertFalse(gap.attributes.inverted)
            XCTAssertEqual(gap.backgroundColor, .blue)
        }
        scrollControl.scroll(to: Position(column: 0, line: 11))
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 0))?.char, "↑")
        node.update(using: content(spacing: 2, visibility: .hidden).view)
        control.layout(size: Size(width: 10, height: 4))
        XCTAssertEqual(scrollControl.children[0].layer.frame.size.width, 7)
        for x in 7 ... 9 {
            XCTAssertEqual(control.layer.cell(at: Position(column: Extended(x), line: 0))?.char, " ")
            XCTAssertEqual(control.layer.cell(at: Position(column: Extended(x), line: 0))?.backgroundColor, .blue)
        }
        node.update(using: content(count: 2, spacing: 2, gutter: .automatic).view)
        control.layout(size: Size(width: 10, height: 4))
        XCTAssertEqual(scrollControl.children[0].layer.frame.size.width, 10)
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 0))?.char, "s")
        XCTAssertEqual(control.layer.cell(at: Position(column: 9, line: 3))?.char, " ")
        node.update(using: content(spacing: .max).view)
        for width in 0 ... 3 {
            for height in 0 ... 3 {
                control.layout(size: Size(width: Extended(width), height: Extended(height)))
                XCTAssertEqual(scrollControl.children[0].layer.frame.size.width, Extended(width > 1 ? 1 : 0))
                if width > 2 && height > 0 {
                    XCTAssertEqual(control.layer.cell(at: Position(column: 1, line: 0))?.char, " ")
                    XCTAssertEqual(control.layer.cell(at: Position(column: 1, line: 0))?.attributes.inverted, false)
                }
            }
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
