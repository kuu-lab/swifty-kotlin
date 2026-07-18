#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeBigDecimalTests {
    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func runtimeString(_ text: String) -> Int {
        Array(text.utf8).withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    private func withFlatString<T>(
        _ text: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(text.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, text.unicodeScalars.count, text.utf8.count, 0)
        }
    }

    @Test
    func testStringToBigDecimalAcceptsScientificNotation() {
        var thrown = 0
        let raw = withFlatString("1.25e3") { data, length, byteCount, hash in
            __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(raw)) == "1.25e3")
    }

    @Test
    func testStringToBigDecimalAcceptsDecimalPointEdgeForms() {
        for value in [".5", "1.", "-.25", "+12.0E-3"] {
            var thrown = 0
            let raw = withFlatString(value) { data, length, byteCount, hash in
                __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown == 0, "Expected \(value) to parse as BigDecimal")
            #expect(stringValue(__kk_bignum_toString(raw)) == value)
        }
    }

    @Test
    func testStringToBigDecimalRejectsWhitespaceWrappedInput() {
        var thrown = 0
        _ = withFlatString(" 12.5 ") { data, length, byteCount, hash in
            __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown != 0)
    }

    @Test
    func testStringToBigDecimalRejectsMalformedInputs() {
        for value in ["", ".", "+", "-", "1e", "1e+", "e10", "NaN"] {
            var thrown = 0
            _ = withFlatString(value) { data, length, byteCount, hash in
                __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown != 0, "Expected \(value) to throw NumberFormatException")
        }
    }

    @Test
    func testStringToBigDecimalOrNullAcceptsScientificNotation() {
        let raw = __kk_string_toBigDecimalOrNull(runtimeString("+.5E-2"))
        #expect(raw != runtimeNullSentinelInt)
        #expect(stringValue(__kk_bignum_toString(raw)) == "+.5E-2")
    }

    @Test
    func testStringToBigDecimalOrNullReturnsNullForInvalidInput() {
        #expect(__kk_string_toBigDecimalOrNull(runtimeString("not-a-number")) == runtimeNullSentinelInt)
        #expect(__kk_string_toBigDecimalOrNull(runtimeString(" 12.5 ")) == runtimeNullSentinelInt)
    }
}
#endif
