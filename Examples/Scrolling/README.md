# Scrolling

Run from this directory in a terminal emulator, using the same SwiftPM workflow as
the other examples:

```sh
swift run
```

The left pane wraps long text, Japanese text, and a combining character. The right
pane contains single-row selectable items. Both use the same scroll state and
scrollbar with a stable gutter.

| Input | Expected result |
| --- | --- |
| Before any input | Both overflowing panes show a scrollbar and a down arrow, including the unfocused list. Complete sentences do not hide the presence of more content. |
| Tab | Switch the input pane. Scrollbars remain visible in both panes. |
| Up/Down or j/k | Move text by a display row; move list selection and reveal that item. |
| Page Up/Page Down | Move by the current body height. On the list this moves selection. |
| Home/End | Reach the first/last text viewport or selected list item. |
| u/d | Browse one page without moving the list selection. |
| g/G | Browse to the start/end without moving the list selection. |
| Resize the terminal | Rewrap text at the final content width, clamp offsets, and use the new viewport height for the next page movement. |
| q, Ctrl-C, Ctrl-D | Quit and restore the terminal. |

At the beginning only the down arrow is present; at the end only the up arrow is
present. In the middle both are present. The thumb indicates position and visible
proportion. Resize large enough to fit all items: the bar disappears while its
column remains reserved. Resize down to very small dimensions: drawing stays inside
each pane, and empty content frames show no invented rows.

Automated range, geometry, snapshot, and declarative-control checks run with
`swift test` from the repository root. These do not constitute visual inspection in
a terminal emulator; use the checks above for that separate verification.
