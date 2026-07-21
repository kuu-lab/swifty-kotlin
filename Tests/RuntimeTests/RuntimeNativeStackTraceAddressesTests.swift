@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeNativeStackTraceAddressesTests {
    @Test func getStackTraceAddressesReturnsRuntimeList() throws {
        let raw = kk_native_getStackTraceAddresses()
        let ptr = try #require(UnsafeMutableRawPointer(bitPattern: raw))
        let list = try #require(tryCast(ptr, to: RuntimeListBox.self))

        #expect(!list.elements.isEmpty)
    }
}
