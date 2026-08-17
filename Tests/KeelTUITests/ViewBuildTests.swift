import XCTest
@testable import KeelTUI

final class ViewBuildTests: XCTestCase {
    @MainActor
    func test_VStack_TupleView2() throws {
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("One")
                    Text("Two")
                }
            }
        }

        let control = try buildView(MyView())
        let treeDescription = control.treeDescription

        XCTAssertEqual(treeDescription, """
            → VStackControl
              → TextControl
              → TextControl
            """)
    }

    @MainActor
    func test_conditional_VStack() throws {
        struct MyView: View {
            @State var value = true

            var body: some View {
                if value {
                    VStack {
                        Text("One")
                    }
                }
            }
        }

        let control = try buildView(MyView())
        let treeDescription = control.treeDescription

        XCTAssertEqual(treeDescription, """
            → VStackControl
              → TextControl
            """)
    }

    @MainActor
    private func buildView<V: View>(_ view: V) throws -> Control {
        let node = Node(view: VStack(content: view).view)
        node.build()
        let control = node.control?.children.first
        return try XCTUnwrap(control)
    }

}
