# Consistent scrolling

Use `TerminalScrollState` for one-dimensional range and movement calculations, and
`TerminalScrollbar` for a vertical indicator and its reserved column. The same
normalized state drives content slicing, movement, and the indicator. Input routing,
focus, selection, and following newly appended content remain application policies.

## Units and ownership

All lengths and offsets in a state use the same unit. Text viewports and modals use
display rows **after wrapping at the final content width**. A selectable list uses
one row per item; it does not wrap items. A table uses one row per record, excluding
its fixed header. Declarative `ScrollView` uses laid-out terminal rows, including
child spacing. Selection indices are not scroll positions.

Low-level components return layout metadata; their caller owns input policy.
Stateful text viewports and lists save normalized offsets when measured or drawn.
Stateless modals and tables expose a layout state that can be moved directly and
passed back as the next offset. Declarative `ScrollView` retains its state internally
and reveals controls using the existing focus mechanism.

## Layout and indicators

First remove borders, titles, fixed headers, and padding from the available frame.
Then allocate the scrollbar gutter, lay out the content at the remaining width,
and resolve its scroll state. `visibility: .whenNeeded` displays an indicator on the
first overflowing frame, independent of focus or input. `.hidden` suppresses it.
`gutter: .stable` reserves a column even when the indicator is hidden or unnecessary;
`.automatic` allocates it only while the indicator is needed and remeasures content
at the reduced width. No indicator overlaps the content.

The default is `.whenNeeded` with `.automatic`. Use `.stable` when wrapping must
remain unchanged as content starts or stops overflowing. A track and thumb show
position and viewport proportion; arrows indicate content before and after the
visible range. One- and two-row indicators retain the direction information.
Glyphs and `TerminalStyle` values are configurable; meaning does not depend on color.

Negative lengths become zero. Empty content resolves to `0..<0`. Offsets are clamped
on initialization and on content/viewport updates. A zero-length viewport has an
empty range, and page movement and range revelation do nothing. Content growth does
not automatically follow the end. Resizing and content shrinkage clamp the saved
offset before the next movement.

These responsibilities follow the separation of content/viewport units in
[Ratatui's ScrollbarState](https://docs.rs/ratatui/latest/ratatui/widgets/struct.ScrollbarState.html),
overflow discovery in [Textual scrolling](https://textual.textualize.io/guide/widgets/#scrolling),
and stable allocation in [Textual scrollbar-gutter](https://textual.textualize.io/styles/scrollbar_gutter/).
Public names and examples follow the emphasis on clarity at the call site in the
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/#fundamentals).

## Caller-owned text and list state

Measure or draw using the current frame before handling input. Drawing updates the
saved offset, and input remeasures against that frame so changed content cannot
leave a stale position behind. Pass `in:` to input or movement when the size changes
before the next draw. Heights exclude borders, titles, padding, and fixed headers.

```swift
var text = TerminalTextViewport(
    lines: ["A complete sentence.", "More content follows.", "日本語 and e\u{301}."],
    scrollbar: TerminalScrollbar(gutter: .stable)
)
let size = TerminalSize(width: 24, height: 2)
let body = TerminalFrame(column: 0, line: 0, width: size.width, height: size.height)
var canvas = TerminalCanvas(size: size)
let layout = text.draw(on: &canvas, frame: body)
// layout.scroll.state and layout.visibleLines describe this exact drawing.
text.handle(.pageDown, in: body)
text.scroll(.end, in: body)
text.draw(on: &canvas, frame: body)

var list = TerminalSelectableList(rows: (1 ... 20).map { "Item \($0)" })
list.handle(.arrowDown, in: body) // changes selection and reveals it
list.scroll(.pages(1), in: body) // changes only the viewing position
list.revealSelection()           // explicitly returns to the selected item
list.draw(on: &canvas, frame: body)
```

List rows are single-line items, clipped horizontally; embedded newlines do not
create extra item rows. For custom multi-line items, lay them out first, map each
item to its display-row range, and call `state.move(.reveal(itemRange))`. This keeps
item identity and selection separate from the shared display-row coordinates.

## Custom content and movement

The measuring closure receives the usable width. It may be called twice with an
automatic gutter. Slice the final laid-out content using the returned state, and
move a copy of that same state before saving its offset. The common calculation
does not assign keys, selection, focus, or a follow-the-end policy.

```swift
let scrollbar = TerminalScrollbar(gutter: .stable)
var offset = 999 // arbitrary caller-owned position; layout will normalize it
let frame = TerminalFrame(column: 0, line: 0, width: 20, height: 4)
var rows: [String] = []
let layout = scrollbar.layout(in: frame, offset: offset) { width in
    rows = TerminalTextLayout.wrap("A long paragraph. 日本語 and e\u{301}.", width: width).map(\.text)
    return rows.count
}
var state = layout.state
offset = state.offset
var canvas = TerminalCanvas(size: TerminalSize(width: 20, height: 4))
for (line, index) in state.visibleRange.enumerated() {
    canvas.draw(rows[index], column: layout.contentFrame.column,
                line: layout.contentFrame.line + line, maxWidth: layout.contentFrame.width)
}
scrollbar.draw(on: &canvas, frame: layout.scrollbarFrame, state: state)
state.move(.pages(1)) // also .units(-1), .start, .end, .reveal(aRange)
offset = state.offset
```

`update(contentLength:viewportLength:)` reuses a retained state after new measurements.
Movement saturates safely even for extreme integer offsets or page counts.
Revealing an empty/outside range does nothing; a range taller than the viewport
aligns its start, clamped to the last valid offset. A zero-width content frame has
a zero-length viewport and an empty visible range, even if it has positive height.
Custom scrollbar glyphs must occupy one display cell; wider or zero-width glyphs
are left blank to avoid writing outside the reserved column.

## Modals, tables, and declarative views

`TerminalModal.layout(in:)` wraps inside borders, title rows, padding, and the
scrollbar gutter. Its `scroll.state` supplies all range and movement information.
`modal.scroll(.pages(1), in: area)` measures, moves, and saves the next offset.
Reading a layout or drawing a modal remains stateless; it does not mutate the
modal's requested offset. Use `scroll(_:in:)`, or copy/move the returned state and
assign its offset, instead of incrementing an unnormalized requested offset.

`TerminalTable.layout(in:rowOffset:maxRows:)` and `draw` return the same shared
layout for the scrolling body. The header consumes one row and never scrolls.
`maxRows` further limits the actual body viewport. Selection highlighting is
independent of `rowOffset`; reveal a selected record explicitly when that is the
desired policy:

```swift
let table = TerminalTable(
    columns: [TerminalTableColumn(header: "Name", width: 12)],
    rows: (1 ... 30).map { TerminalTableRow(cells: [TerminalTableCell("Item \($0)")]) },
    scrollbar: TerminalScrollbar(gutter: .stable)
)
let frame = TerminalFrame(column: 0, line: 0, width: 20, height: 8)
var canvas = TerminalCanvas(size: TerminalSize(width: 20, height: 8))
var state = table.draw(on: &canvas, frame: frame, rowOffset: 999).state
state.move(.pages(-1)) // seven body rows, excluding the fixed header
table.draw(on: &canvas, frame: frame, rowOffset: state.offset)
```

Declarative views need no externally stored offset:

```swift
ScrollView(scrollbar: TerminalScrollbar(gutter: .stable)) {
    ForEach(1 ... 40, id: \.self) { index in
        Button("Item \(index)") { /* application action */ }
    }
}
```

It displays overflow before focus changes, clips children to the content frame, and
uses the shared range-revelation calculation when the existing focus mechanism
selects a control. Content without selectable controls still gets an indicator;
the existing declarative input mechanism only scrolls through focusable controls.
`ScrollView` measures child layout at the final width; it does not change a child's
own layout policy (for example, declarative `Text` remains single-line).

## Migrating from 0.2.0 to 0.3.0

Set the package dependency to
`.package(url: "https://github.com/uchimanajet7/keel-tui", from: "0.3.0")`
to use the APIs described in this guide.

- `TerminalTextViewport.visibleLines(height:)`,
  `TerminalSelectableList.visibleRows(height:)`, and
  `normalizedScrollOffset(height:)` now mutate the retained offset. Declare these
  component values with `var`, and make enclosing rendering methods `mutating`
  when they own those values.
- The height-only text API treats supplied lines as already laid-out display rows.
  Use `layout(in:)` or `draw(on:frame:)` to wrap at the final width with a gutter.
- Key handlers use the last measured viewport; page movement is zero until a
  viewport is measured. Pass the current frame to `handle(_:in:)` for immediate
  input handling. Fixed ten-row paging is removed.
- List slicing no longer continually snaps the viewport to selection. Selection
  movement reveals the selected item; browsing does not. After directly setting
  `selectedIndex`, call `revealSelection()` if needed.
- Text/list drawing, modals, tables, and declarative scroll views show an automatic scrollbar by
  default. To disable it explicitly, pass `TerminalScrollbar(visibility: .hidden)`.
  Choose `.stable` to reserve width even without visible overflow.
- `TerminalModalLayout` metadata is read-only and derived from `scroll`. Its
  initializer now accepts `frame`, `scroll`, `wrappedLines`, and `naturalHeight`,
  replacing independently writable, potentially inconsistent range fields.
- A table's out-of-range `rowOffset` now clamps to the final viewport. `draw` returns
  a discardable `TerminalScrollLayout`; use its state for the next movement.

Run the generic [Scrolling example](https://github.com/uchimanajet7/keel-tui/tree/0.3.0/Examples/Scrolling)
with `swift run` from its directory. Its README describes
keys and expected first-frame, endpoint, selection, and resize behavior. Run
`swift test` at the repository root for automated verification. Terminal-emulator
visual inspection is a separate check.
