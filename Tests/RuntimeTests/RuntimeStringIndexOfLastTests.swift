@testable import Runtime
import XCTest

private let isLetterB: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? 1 : 0
}

private let isLetterZ: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("z").value) ? 1 : 0
}

private func withFlatStringForIndexOfLast<T>(
    _ value: String,
    _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
) -> T {
    var length = 0
    var byteCount = 0
    var hash = 0
    let data = runtimeRegisterFlatString(
        value,
        outLength: &length,
        outByteCount: &byteCount,
        outHash: &hash
    )
    let constData = data.map { UnsafePointer($0) }
    return body(constData, length, byteCount, hash)
}

final class RuntimeStringIndexOfLastTests: XCTestCase {
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

        withFlatStringForIndexOfLast("abcabc") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfLast_flat(
                data,
                length,
                byteCount,
                hash,
                predicate,
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(result, 4)
        }
    }

    func testIndexOfLastReturnsNegativeOneWhenNoMatch() {
        let predicate = unsafeBitCast(isLetterZ, to: Int.self)

        withFlatStringForIndexOfLast("abcabc") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfLast_flat(
                data,
                length,
                byteCount,
                hash,
                predicate,
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(result, -1)
        }
    }

    func testIndexOfLastReturnsNegativeOneForEmptyString() {
        let predicate = unsafeBitCast(isLetterB, to: Int.self)

        withFlatStringForIndexOfLast("") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfLast_flat(
                data,
                length,
                byteCount,
                hash,
                predicate,
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(result, -1)
        }
    }

    func testIndexOfLastReturnsSingleCharIndexWhenOnlyOneMatch() {
        let predicate = unsafeBitCast(isLetterB, to: Int.self)

        withFlatStringForIndexOfLast("abc") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfLast_flat(
                data,
                length,
                byteCount,
                hash,
                predicate,
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(result, 1)
        }
    }
}
