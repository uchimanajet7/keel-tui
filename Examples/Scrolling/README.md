# Scrolling

Run from this directory in a terminal emulator, using the same SwiftPM workflow as
the other examples:

```sh
swift run
```

The example starts with long wrapped text on the left and long selectable list
rows on the right, including Japanese text and a combining character. Press `2`
for a table with a fixed header on the left and a wrapped modal on the right;
press `1` to return. `Tab` selects the input pane in either display.

All four components share `TerminalScrollbar(gutter: .stable, contentSpacing: 1)`.
Press `s` to switch between spacing **1** and **0** without editing source. The
footer shows the current setting. The library default remains 0; 1 is chosen here
to demonstrate separation. At 1, long text and selection backgrounds stop before
a blank column, followed by the bar. At 0 they can meet the bar. The pane areas
stay fixed while text and modal content rewrap at the new content width. When
there is enough room, the modal's natural outer width also includes the reserved
spacing; it remains bounded by its pane area.

| Input | Expected result |
| --- | --- |
| Before any input | Both overflowing panes show a scrollbar and a down arrow, including the unfocused list. Complete sentences do not hide the presence of more content. |
| 1 / 2 | Show Text/List or Table/Modal. Positions and selections are retained. |
| s | Compare content spacing 0/1 in both panes. The gap stays blank, without selection inversion or old text. |
| Tab | Switch the input pane. Scrollbars remain visible in both panes. |
| Up/Down or j/k | Move text/modal by a display row; move list/table selection and reveal that item. |
| Page Up/Page Down | Move by the current body height. On the list/table this moves selection; the table header is excluded. |
| Home/End | Reach the first/last text/modal viewport or selected list/table item. |
| u/d | Browse one page without moving list/table selection. |
| g/G | Browse to the start/end without moving list/table selection. |
| Resize the terminal | Rewrap text at the final content width, clamp offsets, and use the new viewport height for the next page movement. |
| q, Ctrl-C, Ctrl-D | Quit and restore the terminal. |

At the beginning only the down arrow is present; at the end only the up arrow is
present. In the middle both are present. The thumb indicates position and visible
proportion. Resize large enough to fit all items: the bar disappears while its
column and selected spacing remain reserved. The table header stays fixed and
aligned with its body. Resize down to very small dimensions: spacing shrinks first,
drawing stays inside each pane, and empty content frames show no invented rows.

A short comparison: run `swift run`, press `s` twice, then `Tab` and `End` to see a
long selected list row at the bottom. Press `2`, `Tab` to select the table, and
`End`, `s` to compare its selected row and fixed header. Press `Tab`, `Home`, then
`Page Down` to scroll the modal; use `s` again to compare wrapping. Press `q` to exit.

Automated range, geometry, snapshot, and declarative-control checks run with
`swift test` from the repository root. These do not constitute visual inspection in
a terminal emulator; use the checks above for that separate verification.
