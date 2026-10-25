#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeBigDecimalTests {

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
    func testDoubleToBigDecimalPreservesExactJvmValue() {
        let cases: [(Double, String)] = [
            (1.5, "1.5"),
            (0.1, "0.1000000000000000055511151231257827021181583404541015625"),
            (1.0, "1"),
            (-0.0, "0"),
            (1e20, "100000000000000000000"),
        ]

        for (value, expected) in cases {
            var thrown = 0
            let raw = __kk_double_toBigDecimal(Int(bitPattern: UInt(value.bitPattern)), &thrown)
            #expect(thrown == 0)
            #expect(stringValue(__kk_bignum_toString(raw)) == expected)
        }
    }

    @Test
    func testDoubleToBigDecimalRejectsNonFiniteValues() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            var thrown = 0
            _ = __kk_double_toBigDecimal(Int(bitPattern: UInt(value.bitPattern)), &thrown)
            #expect(thrown != 0)
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

    @Test
    func testStringToBigDecimalOrNullFlatAcceptsScientificNotation() {
        let raw = withFlatString("+.5E-2") { data, length, byteCount, hash in
            __kk_string_toBigDecimalOrNull_flat(data, length, byteCount, hash)
        }
        #expect(raw != runtimeNullSentinelInt)
        #expect(stringValue(__kk_bignum_toString(raw)) == "+.5E-2")
    }

    @Test
    func testStringToBigDecimalOrNullFlatReturnsNullForInvalidInput() {
        for value in ["not-a-number", " 12.5 "] {
            let raw = withFlatString(value) { data, length, byteCount, hash in
                __kk_string_toBigDecimalOrNull_flat(data, length, byteCount, hash)
            }
            #expect(raw == runtimeNullSentinelInt, "Expected \(value) to yield null")
        }
    }

    @Test
    func testBigDecimalCompareToComparesNumerically() {
        func box(_ text: String) -> Int {
            var thrown = 0
            let raw = withFlatString(text) { data, length, byteCount, hash in
                __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown == 0, "Expected \(text) to parse as BigDecimal")
            return raw
        }
        #expect(__kk_bignum_compareTo(box("1.5"), box("1.4")) > 0)
        #expect(__kk_bignum_compareTo(box("1.4"), box("1.5")) < 0)
        #expect(__kk_bignum_compareTo(box("1.40"), box("1.4")) == 0)
        #expect(__kk_bignum_compareTo(box("1e3"), box("999")) > 0)
        #expect(__kk_bignum_compareTo(box("0.05"), box("5e-2")) == 0)
        #expect(__kk_bignum_compareTo(box("-0.0"), box("0")) == 0)
        #expect(__kk_bignum_compareTo(box("-2"), box("1")) < 0)
        #expect(__kk_bignum_compareTo(box("-1.5"), box("-1.4")) < 0)
    }

    @Test
    func testBigDecimalArithmeticPreservesPrecisionAndScale() {
        func box(_ text: String) -> Int {
            var thrown = 0
            let raw = withFlatString(text) { data, length, byteCount, hash in
                __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown == 0)
            return raw
        }

        var thrown = 0
        let sum = __kk_bignum_add(box("12345678901234567890.10"), box("0.20"), &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(sum)) == "12345678901234567890.30")

        let difference = __kk_bignum_subtract(box("5.00"), box("7"), &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(difference)) == "-2.00")

        let product = __kk_bignum_multiply(box("-1.20"), box("3.00"), &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(product)) == "-3.6000")
        #expect(__kk_bignum_scale(box("1.230")) == 3)
    }

    @Test
    func testBigDecimalExactAndRoundedDivision() {
        func box(_ text: String) -> Int {
            var thrown = 0
            let raw = withFlatString(text) { data, length, byteCount, hash in
                __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown == 0)
            return raw
        }

        var thrown = 0
        let exact = __kk_bignum_divide(box("1.00"), box("2"), &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(exact)) == "0.50")

        let rounded = __kk_bignum_divideAtScale(box("1"), box("8"), 2, 4, &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(rounded)) == "0.13")

        let floored = __kk_bignum_divideAtScale(box("-1"), box("8"), 2, 3, &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(floored)) == "-0.13")

        _ = __kk_bignum_divide(box("1"), box("3"), &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testBigDecimalSetScaleRoundingAndUnnecessaryMode() {
        func box(_ text: String) -> Int {
            var thrown = 0
            let raw = withFlatString(text) { data, length, byteCount, hash in
                __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown == 0)
            return raw
        }

        var thrown = 0
        let halfUp = __kk_bignum_setScale(box("1.245"), 2, 4, &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(halfUp)) == "1.25")

        let halfEven = __kk_bignum_setScale(box("1.245"), 2, 6, &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(halfEven)) == "1.24")

        let exactScaleChange = __kk_bignum_setScale(box("1000"), -1, 7, &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_bignum_toString(exactScaleChange)) == "1.00E+3")

        _ = __kk_bignum_setScale(box("1.234"), 2, 7, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testBigDecimalNumberConversionsMatchJvmNarrowing() {
        func box(_ text: String) -> Int {
            var thrown = 0
            let raw = withFlatString(text) { data, length, byteCount, hash in
                __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown == 0, "Expected \(text) to parse as BigDecimal")
            return raw
        }

        #expect(__kk_bignum_toDouble(box("0.1")) == 4_591_870_180_066_957_722)
        #expect(__kk_bignum_toFloat(box("0.1")) == 1_036_831_949)
        #expect(__kk_bignum_toDouble(box("-0.0")) == 0)
        #expect(__kk_bignum_toDouble(box("-1e-400")) == Int(bitPattern: UInt(Double(-0.0).bitPattern)))
        #expect(__kk_bignum_toFloat(box("-1e-100")) == Int(bitPattern: UInt(Float(-0.0).bitPattern)))
        #expect(__kk_bignum_toDouble(box("1e400")) == Int(bitPattern: UInt(0x7FF0_0000_0000_0000)))
        #expect(__kk_bignum_toFloat(box("1e400")) == Int(bitPattern: UInt(0x7F80_0000)))

        #expect(__kk_bignum_toLong(box("-129.9")) == -129)
        #expect(__kk_bignum_toInt(box("9223372036854775808.9")) == 0)
        #expect(__kk_bignum_toLong(box("9223372036854775808.9")) == Int.min)
        #expect(__kk_bignum_toLong(box("18446744073709551617.9")) == 1)
        #expect(__kk_bignum_toShort(box("32768.9")) == -32768)
        #expect(__kk_bignum_toByte(box("-129.9")) == 127)
    }

    @Test
    func testBigDecimalNumberConversionDispatch() {
        var thrown = 0
        let value = withFlatString("123.987") { data, length, byteCount, hash in
            __kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)

        #expect(kk_number_to_primitive(value, 0, 0) == __kk_bignum_toDouble(value))
        #expect(kk_number_to_primitive(value, 0, 1) == __kk_bignum_toFloat(value))
        #expect(kk_number_to_primitive(value, 0, 2) == __kk_bignum_toLong(value))
        #expect(kk_number_to_primitive(value, 0, 3) == __kk_bignum_toInt(value))
        #expect(kk_number_to_primitive(value, 0, 4) == __kk_bignum_toShort(value))
        #expect(kk_number_to_primitive(value, 0, 5) == __kk_bignum_toByte(value))
        #expect(kk_number_to_primitive(value, 0, 6) == kk_int_to_char(__kk_bignum_toInt(value)))
    }
}
#endif
