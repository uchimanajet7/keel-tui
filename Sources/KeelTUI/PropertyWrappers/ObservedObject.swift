#if os(macOS)
import Foundation
import Combine

@propertyWrapper
@MainActor
public struct ObservedObject<T: ObservableObject>: AnyObservedObject {
    public let initialValue: T

    public init(initialValue: T) {
        self.initialValue = initialValue
    }

    public init(wrappedValue: T) {
        self.initialValue = wrappedValue
    }

    public var wrappedValue: T {
        get { initialValue }
    }

    func subscribe(_ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable {
        initialValue.objectWillChange.sink { _ in
            Task { @MainActor in
                action()
            }
        }
    }
}

@MainActor
protocol AnyObservedObject {
    func subscribe(_ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable
}

#endif
