// TEST-CHAR-019: Execution tests for isISOControl, Char.minus, String.get, and CharRange.forEach
#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeCharArithmeticTests {

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
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

    @Test
    func testIsISOControl_nulIsControl() {
        #expect(boolValue(kk_char_isISOControl(0x00)))
    }

    @Test
    func testIsISOControl_c0UpperBoundIsControl() {
        // U+001F is the last code point of the C0 control block
        #expect(boolValue(kk_char_isISOControl(0x1F)))
    }

    @Test
    func testIsISOControl_spaceBoundaryIsNotControl() {
        // U+0020 SPACE is the first non-control ASCII character
        #expect(!boolValue(kk_char_isISOControl(0x20)))
    }

    @Test
    func testIsISOControl_delIsControl() {
        // U+007F DEL begins the C1 boundary region
        #expect(boolValue(kk_char_isISOControl(0x7F)))
    }

    @Test
    func testIsISOControl_c1UpperBoundIsControl() {
        // U+009F is the last code point of the C1 control block
        #expect(boolValue(kk_char_isISOControl(0x9F)))
    }

    @Test
    func testIsISOControl_nbspIsNotControl() {
        // U+00A0 NO-BREAK SPACE is the first code point after the C1 block
        #expect(!boolValue(kk_char_isISOControl(0xA0)))
    }

    // MARK: - Char minus Char

    @Test
    func testCharMinusChar_positiveResult() {
        let result = kk_char_minus(kk_box_char(Int(Unicode.Scalar("b").value)),
                                   kk_box_char(Int(Unicode.Scalar("a").value)))
        #expect(result == 1)
    }

    @Test
    func testCharMinusChar_sameChar() {
        let result = kk_char_minus(kk_box_char(Int(Unicode.Scalar("a").value)),
                                   kk_box_char(Int(Unicode.Scalar("a").value)))
        #expect(result == 0)
    }

    @Test
    func testCharMinusChar_negativeResult() {
        let result = kk_char_minus(kk_box_char(Int(Unicode.Scalar("a").value)),
                                   kk_box_char(Int(Unicode.Scalar("b").value)))
        #expect(result == -1)
    }

    @Test
    func testCharMinusChar_largeSpan() {
        // 'z' (122) - 'a' (97) = 25
        let result = kk_char_minus(kk_box_char(Int(Unicode.Scalar("z").value)),
                                   kk_box_char(Int(Unicode.Scalar("a").value)))
        #expect(result == 25)
    }

    // MARK: - String.get

    @Test
    func testStringGet_normalAccess() {
        withFlatString("hello") { data, length, byteCount, hash in
            var outThrown: Int = 0
            let ch = kk_string_get_flat(data, length, byteCount, hash, 1, &outThrown)
            #expect(outThrown == 0)
            #expect(ch == Int(Unicode.Scalar("e").value))
        }
    }

    @Test
    func testStringGet_firstChar() {
        withFlatString("world") { data, length, byteCount, hash in
            var outThrown: Int = 0
            let ch = kk_string_get_flat(data, length, byteCount, hash, 0, &outThrown)
            #expect(outThrown == 0)
            #expect(ch == Int(Unicode.Scalar("w").value))
        }
    }

    @Test
    func testStringGet_outOfBounds_throws() {
        withFlatString("hi") { data, length, byteCount, hash in
            var outThrown: Int = 0
            _ = kk_string_get_flat(data, length, byteCount, hash, 5, &outThrown)
            #expect(outThrown != 0, "index 5 on length-2 string must throw")
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

    @Test
    func testCharRangeForEach_ascending() {
        let collect = makeCollector()
        var result: [Int] = []
        withUnsafeMutablePointer(to: &result) { buf in
            let range = kk_op_rangeTo(kk_box_char(Int(Unicode.Scalar("a").value)),
                                      kk_box_char(Int(Unicode.Scalar("e").value)))
            _ = kk_char_range_forEach(range, unsafeBitCast(collect, to: Int.self),
                                  Int(bitPattern: buf), nil)
        }
        #expect(result == [97, 98, 99, 100, 101])
    }

    @Test
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
        #expect(result == [], "empty CharRange (first > last, step=1) must produce zero iterations")
    }

    @Test
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
        #expect(result == [101, 100, 99, 98, 97])
    }
}
#endif
