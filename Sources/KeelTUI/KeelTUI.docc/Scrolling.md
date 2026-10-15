# Consistent scrolling

Use `TerminalScrollState` for one-dimensional range and movement calculations, and
`TerminalScrollbar` for a vertical indicator, its reserved column, and content spacing. The same
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
Then resolve three disjoint regions in order: **content → spacing → scrollbar**.
Measure and wrap at the final `contentFrame.width`, then resolve the scroll state
from those rows and the content viewport. `TerminalScrollLayout` exposes read-only
`contentFrame`, `spacingFrame`, and `scrollbarFrame` values for measurement, clipping,
and drawing without duplicating width or coordinate calculations.

The three independent settings are:

| Setting | Meaning |
| --- | --- |
| `visibility` | `.whenNeeded` draws overflow immediately, independently of focus; `.hidden` suppresses the indicator. |
| `gutter` | `.stable` always reserves the bar and spacing, even for empty/fitting content or hidden visibility. `.automatic` reserves them only when a visible bar is needed. |
| `contentSpacing` | Integer display cells between content and the one-column bar, reserved only with the gutter. Defaults to **0**, preserving existing widths and wrapping. |

Content spacing requires KeelTUI 0.4.0 or later.

With `.automatic` and `.whenNeeded`, measure without reservation first. Only if
those rows exceed the viewport, allocate both bar and spacing and measure again at
the final content width. `.automatic` with `.hidden` reserves neither. With
`.stable`, the content width stays the same for a given frame and configuration
regardless of content length, focus, or indicator visibility.

The examples explicitly choose `contentSpacing: 1` to show separation. One cell is
an optional choice, not a universal standard. Negative values act as zero, including
after assignment. Large values are bounded before arithmetic can overflow. Spacing
shrinks first to preserve one content cell when possible: a reserved bar in width
2 uses content 1, spacing 0, bar 1; width 1 uses content 0, spacing 0, bar 1. Width
0 or height 0 draws nothing. Wide and combining characters retain the existing
grapheme and display-width behavior and are never split to fit a narrow frame.

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
    scrollbar: TerminalScrollbar(gutter: .stable, contentSpacing: 1)
)
let size = TerminalSize(width: 24, height: 2)
let body = TerminalFrame(column: 0, line: 0, width: size.width, height: size.height)
var canvas = TerminalCanvas(size: size)
let layout = text.draw(on: &canvas, frame: body)
// layout.scroll.state and layout.visibleLines describe this exact drawing.
text.handle(.pageDown, in: body)
text.scroll(.end, in: body)
text.draw(on: &canvas, frame: body)

var list = TerminalSelectableList(
    rows: (1 ... 20).map { "Item \($0)" },
    scrollbar: TerminalScrollbar(gutter: .stable, contentSpacing: 1)
)
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
let scrollbar = TerminalScrollbar(gutter: .stable, contentSpacing: 1)
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
canvas.clear(frame: frame) // also clear content when reusing a canvas
for (line, index) in state.visibleRange.enumerated() {
    canvas.draw(rows[index], column: layout.contentFrame.column,
                line: layout.contentFrame.line + line, maxWidth: layout.contentFrame.width)
}
scrollbar.draw(on: &canvas, layout: layout) // clears spacing and draws/clears the bar
state.move(.pages(1)) // also .units(-1), .start, .end, .reveal(aRange)
offset = state.offset
```

The layout-based drawing path clears spacing with a normal background and no
selection, inversion, or emphasis. For a custom surface, use
`canvas.clear(frame: frame, style: TerminalStyle(background: .blue))` and
`scrollbar.draw(on: &canvas, layout: layout, background: .blue)`, and use that
background for normal content too. Redraw the content on selection, size, settings,
or content changes; regions released by an automatic gutter belong to content
again. The built-in components clear their supplied frames on every draw. When a
caller moves or shrinks an outer frame, it must repaint the area it previously
owned; component drawing never owns the area outside its current frame.

`draw(on:frame:state:)` retains its original bar-only meaning: it writes only in
the supplied scrollbar column and does not clear adjacent spacing.

`update(contentLength:viewportLength:)` reuses a retained state after new measurements.
Movement saturates safely even for extreme integer offsets or page counts.
Revealing an empty/outside range does nothing; a range taller than the viewport
aligns its start, clamped to the last valid offset. A zero-width content frame has
a zero-length viewport and an empty visible range, even if it has positive height.
Custom scrollbar glyphs must occupy one display cell; wider or zero-width glyphs
are left blank to avoid writing outside the reserved column.

## Modals, tables, and declarative views

`TerminalModal.layout(in:)` wraps inside borders, title rows, padding, and the
scrollbar and spacing. Natural width includes the stable gutter's reservation;
preferred, minimum, maximum, and caller-area bounds still apply. An explicit frame
is never enlarged for spacing. Automatic gutters also preserve the existing
content-derived outer width: reservation is decided inside that chosen width and
bounded body height, then wrapping and height are resolved again using
the common layout. Measurement and drawing use the same final content width.
Its `scroll.state` supplies all range and movement information.
`modal.scroll(.pages(1), in: area)` measures, moves, and saves the next offset.
Reading a layout or drawing a modal remains stateless; it does not mutate the
modal's requested offset. Use `scroll(_:in:)`, or copy/move the returned state and
assign its offset, instead of incrementing an unnormalized requested offset.

`TerminalTable.layout(in:rowOffset:maxRows:)` and `draw` return the same shared
layout for the scrolling body. The header uses the same content width, consumes
one row, and never scrolls.
`maxRows` further limits the actual body viewport. Selection highlighting is
independent of `rowOffset`; reveal a selected record explicitly when that is the
desired policy:

```swift
let table = TerminalTable(
    columns: [TerminalTableColumn(header: "Name", width: 12)],
    rows: (1 ... 30).map { TerminalTableRow(cells: [TerminalTableCell("Item \($0)")]) },
    scrollbar: TerminalScrollbar(gutter: .stable, contentSpacing: 1)
)
let frame = TerminalFrame(column: 0, line: 0, width: 20, height: 8)
var canvas = TerminalCanvas(size: TerminalSize(width: 20, height: 8))
var state = table.draw(on: &canvas, frame: frame, rowOffset: 999).state
state.move(.pages(-1)) // seven body rows, excluding the fixed header
table.draw(on: &canvas, frame: frame, rowOffset: state.offset)
```

Declarative views need no externally stored offset:

```swift
ScrollView(scrollbar: TerminalScrollbar(gutter: .stable, contentSpacing: 1)) {
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
An enclosing `.background(...)` also supplies the spacing background without
inheriting a child's selected or highlighted appearance. Canvas text viewports,
lists, tables, and modals accept `background:` on `draw` for the normal surface.
It defaults to the terminal background, preserving existing rendering. Content,
row, selection, and scrollbar styles can override it for their own cells without
affecting spacing. For example, use `list.draw(on: &canvas, frame: body,
background: .blue)` to fill its normal surface, including spacing, with blue.

## Migrating from 0.2.0 to 0.3.0

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

## Running the example

Run the generic Scrolling example in the repository's `Examples/Scrolling`
with `swift run` from its directory. Its README describes
keys to compare spacing 0/1 in text, list, table, and modal displays, plus expected
first-frame, endpoint, selection, and resize behavior. Run
`swift test` at the repository root for automated verification. Terminal-emulator
visual inspection is a separate check.
