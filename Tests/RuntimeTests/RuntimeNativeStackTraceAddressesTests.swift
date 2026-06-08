@testable import Runtime
import XCTest

final class RuntimeNativeStackTraceAddressesTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    func testGetStackTraceAddressesReturnsRuntimeList() throws {
        let raw = kk_native_getStackTraceAddresses()
        let ptr = try XCTUnwrap(UnsafeMutableRawPointer(bitPattern: raw))
        let list = try XCTUnwrap(tryCast(ptr, to: RuntimeListBox.self))

        XCTAssertFalse(list.elements.isEmpty)
    }
}
