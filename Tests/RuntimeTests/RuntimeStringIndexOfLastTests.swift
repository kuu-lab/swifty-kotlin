@testable import Runtime
import XCTest

private let isLetterB: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? 1 : 0
}

private let isLetterZ: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("z").value) ? 1 : 0
}

final class RuntimeStringIndexOfLastTests: XCTestCase {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, text.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testIndexOfLastReturnsLastMatchingIndex() {
        let predicate = unsafeBitCast(isLetterB, to: Int.self)
        var thrown = 0
        let result = kk_string_indexOfLast(runtimeString("abcabc"), predicate, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 4)
    }

    func testIndexOfLastReturnsNegativeOneWhenNoMatch() {
        let predicate = unsafeBitCast(isLetterZ, to: Int.self)
        var thrown = 0
        let result = kk_string_indexOfLast(runtimeString("abcabc"), predicate, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, -1)
    }

    func testIndexOfLastReturnsNegativeOneForEmptyString() {
        let predicate = unsafeBitCast(isLetterB, to: Int.self)
        var thrown = 0
        let result = kk_string_indexOfLast(runtimeString(""), predicate, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, -1)
    }

    func testIndexOfLastReturnsSingleCharIndexWhenOnlyOneMatch() {
        let predicate = unsafeBitCast(isLetterB, to: Int.self)
        var thrown = 0
        let result = kk_string_indexOfLast(runtimeString("abc"), predicate, 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 1)
    }
}
