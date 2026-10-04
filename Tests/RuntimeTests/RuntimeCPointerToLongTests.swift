#if canImport(Testing)
import Testing
@testable import Runtime

// Runtime-level tests for kk_cpointer_toLong / kk_cpointer_address.
//
// A Kotlin-source E2E codegen test for the non-null case cannot be written yet
// because CVar.ptr (needed to obtain a CPointer<T> from an alloc) is not
// implemented.  These Swift tests directly exercise the runtime path so that a
// regression that makes kk_cpointer_toLong always return 0 is caught.
@Suite
struct RuntimeCPointerToLongTests {

    @Test
    func testCPointerToLongNullSentinelReturnsZero() {
        #expect(kk_cpointer_toLong(0) == 0)
        #expect(kk_cpointer_toLong(runtimeNullSentinelInt) == 0)
    }

    @Test
    func testCPointerToLongNonNullReturnsAddress() throws {
        let expectedAddress: UInt = 0x1234_5678
        let handle = kk_cpointer_new(Int(bitPattern: expectedAddress))
        #expect(handle != 0, "kk_cpointer_new must return a non-zero handle")

        let result = kk_cpointer_toLong(handle)
        #expect(result == Int(bitPattern: expectedAddress),
                "toLong() should return the raw pointer address")
    }

    @Test
    func testCPointerAddressNonNullReturnsAddress() throws {
        let expectedAddress: UInt = 0xDEAD_BEEF
        let handle = kk_cpointer_new(Int(bitPattern: expectedAddress))
        #expect(handle != 0)

        let result = kk_cpointer_address(handle)
        #expect(result == Int(bitPattern: expectedAddress))
    }

    @Test
    func testCPointerToLongUnregisteredHandleReturnsZero() {
        // A random non-zero value that is NOT a registered runtime object.
        let fakeHandle = 0x9999
        #expect(kk_cpointer_toLong(fakeHandle) == 0)
    }
}
#endif
