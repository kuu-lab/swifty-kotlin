import Foundation

struct RuntimeFormatError: Error {
    let kind: String
    let message: String
}

private final class RuntimeFormatExceptionBox: RuntimeThrowableBox {
    let kind: String

    init(_ error: RuntimeFormatError) {
        kind = error.kind
        super.init(message: error.message, cause: 0)
    }

    override var exceptionFQName: String { "java.util.\(kind)" }
    override var exceptionHierarchyFQNames: [String] {
        [exceptionFQName, "java.util.IllegalFormatException", "kotlin.IllegalArgumentException",
         "kotlin.RuntimeException", "kotlin.Exception", "kotlin.Throwable"]
    }
    override var renderedMessage: String { runtimeRenderedExceptionMessage(kind, message) }
}

func runtimeAllocateFormatException(_ error: RuntimeFormatError) -> Int {
    let pointer = UnsafeMutableRawPointer(Unmanaged.passRetained(RuntimeFormatExceptionBox(error)).toOpaque())
    runtimeStorage.withGCLock { $0.objectPointers.insert(UInt(bitPattern: pointer)) }
    return Int(bitPattern: pointer)
}
