// TEST-CHAR-019: Execution tests for isISOControl, Char.minus, String.get, and CharRange.forEach
@testable import Runtime
import XCTest

final class RuntimeCharArithmeticTests: XCTestCase {

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func withFlatString<T>(
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

    // MARK: - isISOControl

    func testIsISOControl_nulIsControl() {
        XCTAssertTrue(boolValue(kk_char_isISOControl(0x00)))
    }

    func testIsISOControl_c0UpperBoundIsControl() {
        // U+001F is the last code point of the C0 control block
        XCTAssertTrue(boolValue(kk_char_isISOControl(0x1F)))
    }

    func testIsISOControl_spaceBoundaryIsNotControl() {
        // U+0020 SPACE is the first non-control ASCII character
        XCTAssertFalse(boolValue(kk_char_isISOControl(0x20)))
    }

    func testIsISOControl_delIsControl() {
        // U+007F DEL begins the C1 boundary region
        XCTAssertTrue(boolValue(kk_char_isISOControl(0x7F)))
    }

    func testIsISOControl_c1UpperBoundIsControl() {
        // U+009F is the last code point of the C1 control block
        XCTAssertTrue(boolValue(kk_char_isISOControl(0x9F)))
    }

    func testIsISOControl_nbspIsNotControl() {
        // U+00A0 NO-BREAK SPACE is the first code point after the C1 block
        XCTAssertFalse(boolValue(kk_char_isISOControl(0xA0)))
    }

    // MARK: - Char minus Char

    func testCharMinusChar_positiveResult() {
        let result = kk_char_minus(kk_box_char(Int(Unicode.Scalar("b").value)),
                                   kk_box_char(Int(Unicode.Scalar("a").value)))
        XCTAssertEqual(result, 1)
    }

    func testCharMinusChar_sameChar() {
        let result = kk_char_minus(kk_box_char(Int(Unicode.Scalar("a").value)),
                                   kk_box_char(Int(Unicode.Scalar("a").value)))
        XCTAssertEqual(result, 0)
    }

    func testCharMinusChar_negativeResult() {
        let result = kk_char_minus(kk_box_char(Int(Unicode.Scalar("a").value)),
                                   kk_box_char(Int(Unicode.Scalar("b").value)))
        XCTAssertEqual(result, -1)
    }

    func testCharMinusChar_largeSpan() {
        // 'z' (122) - 'a' (97) = 25
        let result = kk_char_minus(kk_box_char(Int(Unicode.Scalar("z").value)),
                                   kk_box_char(Int(Unicode.Scalar("a").value)))
        XCTAssertEqual(result, 25)
    }

    // MARK: - String.get

    func testStringGet_normalAccess() {
        withFlatString("hello") { data, length, byteCount, hash in
            var outThrown: Int = 0
            let ch = kk_string_get_flat(data, length, byteCount, hash, 1, &outThrown)
            XCTAssertEqual(outThrown, 0)
            XCTAssertEqual(ch, Int(Unicode.Scalar("e").value))
        }
    }

    func testStringGet_firstChar() {
        withFlatString("world") { data, length, byteCount, hash in
            var outThrown: Int = 0
            let ch = kk_string_get_flat(data, length, byteCount, hash, 0, &outThrown)
            XCTAssertEqual(outThrown, 0)
            XCTAssertEqual(ch, Int(Unicode.Scalar("w").value))
        }
    }

    func testStringGet_outOfBounds_throws() {
        withFlatString("hi") { data, length, byteCount, hash in
            var outThrown: Int = 0
            _ = kk_string_get_flat(data, length, byteCount, hash, 5, &outThrown)
            XCTAssertNotEqual(outThrown, 0, "index 5 on length-2 string must throw")
        }
    }

    // MARK: - CharRange.forEach
    //
    // @convention(c) lambdas cannot capture variables from the enclosing scope.
    // The closureRaw parameter is used to pass a pointer to the result array,
    // mirroring the pattern that compiled Kotlin lambdas use.

    private func makeCollector() -> (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) {
        return { closureRaw, value, _ in
            let buf = UnsafeMutablePointer<[Int]>(bitPattern: closureRaw)!
            buf.pointee.append(value)
            return 0
        }
    }

    func testCharRangeForEach_ascending() {
        let collect = makeCollector()
        var result: [Int] = []
        withUnsafeMutablePointer(to: &result) { buf in
            let range = kk_op_rangeTo(kk_box_char(Int(Unicode.Scalar("a").value)),
                                      kk_box_char(Int(Unicode.Scalar("e").value)))
            _ = kk_char_range_forEach(range, unsafeBitCast(collect, to: Int.self),
                                  Int(bitPattern: buf), nil)
        }
        XCTAssertEqual(result, [97, 98, 99, 100, 101])
    }

    func testCharRangeForEach_emptyRange() {
        // first ('e'=101) > last ('a'=97) with step=1 → while 101 <= 97 is false immediately
        let collect = makeCollector()
        var result: [Int] = []
        withUnsafeMutablePointer(to: &result) { buf in
            let range = kk_op_rangeTo(kk_box_char(Int(Unicode.Scalar("e").value)),
                                      kk_box_char(Int(Unicode.Scalar("a").value)))
            _ = kk_char_range_forEach(range, unsafeBitCast(collect, to: Int.self),
                                  Int(bitPattern: buf), nil)
        }
        XCTAssertEqual(result, [], "empty CharRange (first > last, step=1) must produce zero iterations")
    }

    func testCharRangeForEach_descending() {
        // 'e' downTo 'a' has step=-1; forEach uses the negative-step branch
        let collect = makeCollector()
        var result: [Int] = []
        withUnsafeMutablePointer(to: &result) { buf in
            let range = kk_op_downTo(kk_box_char(Int(Unicode.Scalar("e").value)),
                                     kk_box_char(Int(Unicode.Scalar("a").value)))
            _ = kk_char_range_forEach(range, unsafeBitCast(collect, to: Int.self),
                                  Int(bitPattern: buf), nil)
        }
        XCTAssertEqual(result, [101, 100, 99, 98, 97])
    }
}
