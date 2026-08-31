@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeNativeStackTraceAddressesTests {
    @Test func getStackTraceAddressesReturnsRuntimeList() throws {
        let throwableRaw = runtimeAllocateThrowable(message: "captured")
        let raw = kk_native_getStackTraceAddresses(throwableRaw)
        let ptr = try #require(UnsafeMutableRawPointer(bitPattern: raw))
        let list = try #require(tryCast(ptr, to: RuntimeListBox.self))
        let throwablePtr = try #require(UnsafeMutableRawPointer(bitPattern: throwableRaw))
        let throwable = try #require(tryCast(throwablePtr, to: RuntimeThrowableBox.self))

        #expect(!list.elements.isEmpty)
        #expect(list.elements == throwable.stackTraceAddresses)
    }
}
