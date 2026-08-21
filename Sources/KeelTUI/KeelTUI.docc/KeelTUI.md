# ``KeelTUI``

A general-purpose terminal user interface toolkit for Swift applications on macOS 26 and later.

## Documentation

This generated documentation can serve as a reference for the currently supported functionality. Also check out `README.md` and the included example projects.

## Getting started

KeelTUI uses Swift tools version 6.3 and targets macOS 26 or later. Add KeelTUI to an executable Swift package with the following `Package.swift`:

```swift
// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "MyTerminalApp",
  platforms: [
    .macOS(.v26)
  ],
  dependencies: [
    .package(
      url: "https://github.com/uchimanajet7/keel-tui",
      from: "0.1.0"
    )
  ],
  targets: [
    .executableTarget(
      name: "MyTerminalApp",
      dependencies: [
        .product(name: "KeelTUI", package: "keel-tui")
      ]
    )
  ]
)
```

Import KeelTUI and compose terminal interfaces with the supported views, modifiers, and terminal primitives.

```swift
import KeelTUI

struct MyTerminalView: View {
  var body: some View {
    Text("Hello, world!")
  }
}
```

Add the following to `main.swift` to start the terminal application using one of your views as the root view.

```swift
Application(
  rootView: MyTerminalView()
)
.start()
```

To run the app, open a terminal emulator such as macOS's Terminal app, change to your package's directory and run

```bash
swift run
```

## Terminal presentation primitives

`TerminalStatusBar` measures complete shortcut-and-label items, including outer padding and separators. Full labels are preferred, then lower `retentionPriority` items use compact labels, then lower-priority items are omitted. Later items lose ties. The text and canvas paths use the same resolved item layout.

`TerminalTextLayout` preserves Swift `Character` boundaries, explicit and empty logical lines, styles, and continuation indents. Its `wordBoundary` policy prefers whitespace and hard-wraps unbroken tokens. It is not a complete Unicode line-breaking algorithm. At width zero, each logical input line becomes one empty output line. An over-wide continuation indent is truncated to reserve one content cell. A single `Character` wider than that cell remains atomic, and `TerminalCanvas` draws it only when its complete cell width fits.

`TerminalModal` wraps after choosing its content width. `layout(in:)` exposes the natural height, wrapped and visible lines, visible range, normalized scroll offset, and maximum scroll offset. Rendering does not handle input; the application supplies the scroll state.

`TerminalKeyBindingPresentation` is a display-only descriptor shared by status and grouped-help adapters. Both adapters require an explicit disabled-binding visibility policy.

```swift
let bindings = [
  TerminalKeyBindingPresentation(
    id: "help",
    shortcut: "?",
    description: "Show help",
    compactDescription: "Help",
    groupID: "general",
    groupTitle: "General",
    retentionPriority: 50
  )
]

let status = TerminalStatusBar(
  items: bindings.statusBarItems(disabledVisibility: .exclude)
)
let help = TerminalModal(
  title: "Help",
  styledLines: TerminalBindingHelp.lines(
    from: bindings,
    width: 40,
    disabledVisibility: .include
  ),
  preferredWidth: 44,
  maximumHeight: 18
)
```

## Topics

### Application

- ``Application``

### View

- ``View``
- ``ViewBuilder``
- ``Group``
- ``ForEach``
- ``EmptyView``

### Layout

- ``VStack``
- ``HStack``
- ``ZStack``
- ``Spacer``
- ``Divider``
- ``View/frame(width:height:alignment:)``
- ``View/frame(minWidth:maxWidth:minHeight:maxHeight:alignment:)``
- ``View/padding(_:)``
- ``View/padding(_:_:)``
- ``GeometryReader``
- ``Alignment``
- ``HorizontalAlignment``
- ``VerticalAlignment``
- ``Edges``
- ``Extended``
- ``Size``

### Style

- ``Color``
- ``View/foregroundColor(_:)``
- ``View/background(_:)``
- ``View/border(_:style:)``
- ``BorderStyle``
- ``DividerStyle``

### Text

- ``Text``
- ``View/bold(_:)``
- ``View/italic(_:)``
- ``View/strikethrough(_:)``
- ``View/underline(_:)``

### Controls

- ``ScrollView``
- ``Button``
- ``TextField``
- ``EnvironmentValues/placeholderColor``

### View lifecycle

- ``View/onAppear(_:)``

### Property wrappers

- ``State``
- ``Binding``
- ``ObservedObject``
- ``Environment``
- ``View/environment(_:_:)``
- ``EnvironmentKey``
- ``EnvironmentValues``

### Debugging

- ``log(_:terminator:)``

### Terminal primitives

- ``TerminalCanvas``
- ``TerminalDisplayWidth``
- ``TerminalStatusBar``
- ``TerminalStatusBarItem``
- ``TerminalTextLayout``
- ``TerminalTextWrapPolicy``
- ``TerminalStyledTextSegment``
- ``TerminalModal``
- ``TerminalModalLine``
- ``TerminalModalLayout``
- ``TerminalKeyBindingPresentation``
- ``TerminalKeyBindingPresentationAdapter``
- ``TerminalBindingHelp``
- ``TerminalDisabledBindingVisibility``
- ``TerminalBindingHelpKeyColumnScope``
