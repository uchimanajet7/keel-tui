import Foundation

/// A vertical viewport that reveals focused controls and indicates overflow immediately.
///
/// State is retained internally in laid-out terminal rows. Input and focus continue to use
/// the existing control hierarchy; an indicator does not require selectable content.
public struct ScrollView<Content: View>: View, PrimitiveView {
    let content: VStack<Content>
    let scrollbar: TerminalScrollbar

    /// Creates a viewport with configurable visibility, gutter reservation, and content spacing.
    /// Spacing uses the view's normal background and defaults to zero.
    public init(scrollbar: TerminalScrollbar = TerminalScrollbar(), @ViewBuilder _ content: () -> Content) {
        self.content = VStack(content: content())
        self.scrollbar = scrollbar
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        let control = ScrollControl(scrollbar: scrollbar)
        control.contentControl = node.children[0].control(at: 0)
        control.viewportControl.addSubview(control.contentControl, at: 0)
        control.addSubview(control.viewportControl, at: 0)
        control.addSubview(control.indicatorControl, at: 1)
        node.control = control
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.control as! ScrollControl
        control.scrollbar = scrollbar
        control.layer.invalidate()
    }

    private class ScrollControl: Control {
        var contentControl: Control!
        let viewportControl = Control()
        let indicatorControl = ScrollbarControl()
        var scrollbar: TerminalScrollbar
        var state = TerminalScrollState(contentLength: 0, viewportLength: 0)
        var pendingDestination: Int?

        init(scrollbar: TerminalScrollbar) {
            self.scrollbar = scrollbar
        }

        override func layout(size: Size) {
            super.layout(size: size)
            let frame = TerminalFrame(column: 0, line: 0, width: max(0, size.width.intValue),
                                      height: max(0, size.height.intValue))
            var layout = scrollbar.layout(in: frame, offset: state.offset) { width in
                let contentSize = self.contentControl.size(proposedSize: Size(width: Extended(width), height: 0))
                return contentSize.height.intValue
            }
            state = layout.state
            viewportControl.layout(size: Size(width: Extended(layout.contentFrame.width), height: size.height))
            contentControl.layout(size: Size(width: Extended(layout.contentFrame.width), height: Extended(state.contentLength)))
            if let destination = pendingDestination, state.viewportLength > 0 {
                state.move(.reveal(destination ..< destination + 1))
                pendingDestination = nil
            }
            contentControl.layer.frame.position.line = Extended(-state.offset)
            indicatorControl.layer.frame = Rect(
                position: Position(column: Extended(layout.gutterFrame.column), line: 0),
                size: Size(width: Extended(layout.gutterFrame.width), height: size.height)
            )
            indicatorControl.scrollbar = scrollbar
            layout.state = state
            indicatorControl.scrollLayout = layout
        }

        override func scroll(to position: Position) {
            let destination = max(0, (position.line - contentControl.layer.frame.position.line).intValue)
            pendingDestination = destination
            guard state.viewportLength > 0 else { return }
            state.move(.reveal(destination ..< destination + 1))
            pendingDestination = nil
            contentControl.layer.frame.position.line = Extended(-state.offset)
            indicatorControl.scrollLayout?.state = state
            layer.invalidate()
        }
    }

    private class ScrollbarControl: Control {
        var scrollbar = TerminalScrollbar() {
            didSet { if oldValue != scrollbar { layer.invalidate() } }
        }
        var scrollLayout: TerminalScrollLayout? {
            didSet { if oldValue != scrollLayout { layer.invalidate() } }
        }

        override func cell(at position: Position) -> Cell? {
            guard let layout = scrollLayout,
                  let value = scrollbar.cell(
                    column: position.column.intValue + layout.gutterFrame.column,
                    line: position.line.intValue + layout.gutterFrame.line, layout: layout,
                    geometry: TerminalScrollbarGeometry(state: layout.state, length: layout.scrollbarFrame.height)
                  ) else { return nil }
            return Cell(char: value.glyph, foregroundColor: value.style.foreground ?? .default,
                        backgroundColor: value.style.background,
                        attributes: CellAttributes(bold: value.style.isBold, dim: value.style.isDim,
                                                   inverted: value.style.isReversed))
        }
    }
}
