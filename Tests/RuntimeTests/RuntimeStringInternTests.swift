import XCTest
@testable import Runtime

/// STDLIB-TEXT-FN-026: Tests for the kk_string_intern runtime ABI.
final class RuntimeStringInternTests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    private func makeRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func stringFromRaw(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else { return "" }
        return box.value
    }

    func testInternReturnsEquivalentString() {
        let raw = makeRaw("hello")
        let interned = kk_string_intern(raw)
        XCTAssertEqual(stringFromRaw(interned), "hello")
    }

    func testInternOfEmptyString() {
        let raw = makeRaw("")
        let interned = kk_string_intern(raw)
        XCTAssertEqual(stringFromRaw(interned), "")
    }

    func testInternIsIdempotent() {
        let raw = makeRaw("idempotent")
        let interned1 = kk_string_intern(raw)
        let interned2 = kk_string_intern(interned1)
        XCTAssertEqual(interned1, interned2)
    }
}
