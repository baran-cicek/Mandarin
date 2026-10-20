import Foundation

/// A Sendable weak reference, so closures that hop to the main actor do not
/// capture a mutable `self` (older Swift compilers reject that).
final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
