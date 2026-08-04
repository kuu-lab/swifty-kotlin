@testable import Runtime
import Testing

@Suite
struct RuntimeBigIntegerTests {
    private struct BigIntegerParseFailure: Error {
        let text: String
    }

    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func withFlatString<T>(
        _ text: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(text.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, text.unicodeScalars.count, text.utf8.count, 0)
        }
    }

    private func bigInteger(_ text: String) throws -> Int {
        var thrown = 0
        let raw = kk_biginteger_fromString(runtimeString(text), &thrown)
        guard thrown == 0 else {
            throw BigIntegerParseFailure(text: text)
        }
        return raw
    }

    @Test
    func testStringToBigIntegerAcceptsSignedDigits() {
        var thrown = 0
        let raw = withFlatString("-12345678901234567890") { data, length, byteCount, hash in
            __kk_string_toBigInteger_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        #expect(stringValue(__kk_biginteger_toString(raw)) == "-12345678901234567890")
    }

    @Test
    func testStringToBigIntegerAcceptsLeadingPlusAndZeros() {
        var thrown = 0
        let raw = withFlatString("+00012345678901234567890") { data, length, byteCount, hash in
            __kk_string_toBigInteger_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        #expect(stringValue(__kk_biginteger_toString(raw)) == "12345678901234567890")
    }

    @Test
    func testStringToBigIntegerReturnsBigIntegerBoxUsableByOperations() throws {
        var thrown = 0
        let lhs = withFlatString("12345678901234567890") { data, length, byteCount, hash in
            __kk_string_toBigInteger_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        let rhs = try bigInteger("10")
        let result = kk_biginteger_add(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "12345678901234567900")
    }

    @Test
    func testStringToBigIntegerRejectsDecimalPoint() {
        var thrown = 0
        _ = withFlatString("12.5") { data, length, byteCount, hash in
            __kk_string_toBigInteger_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown != 0)
    }

    @Test
    func testStringToBigIntegerOrNullAcceptsSignedDigits() {
        let raw = __kk_string_toBigIntegerOrNull(runtimeString("+00012345678901234567890"))
        #expect(raw != runtimeNullSentinelInt)
        #expect(stringValue(__kk_biginteger_toString(raw)) == "12345678901234567890")
    }

    @Test
    func testStringToBigIntegerOrNullRejectsInvalidInput() {
        #expect(__kk_string_toBigIntegerOrNull(runtimeString("12.5")) == runtimeNullSentinelInt)
        #expect(__kk_string_toBigIntegerOrNull(runtimeString("")) == runtimeNullSentinelInt)
        #expect(__kk_string_toBigIntegerOrNull(runtimeString(" 12 ")) == runtimeNullSentinelInt)
    }

    @Test
    func testStringToBigIntegerOrNullFlatAcceptsSignedDigits() {
        let raw = withFlatString("+00012345678901234567890") { data, length, byteCount, hash in
            __kk_string_toBigIntegerOrNull_flat(data, length, byteCount, hash)
        }
        #expect(raw != runtimeNullSentinelInt)
        #expect(stringValue(__kk_biginteger_toString(raw)) == "12345678901234567890")
    }

    @Test
    func testStringToBigIntegerOrNullFlatRejectsInvalidInput() {
        for value in ["12.5", "", " 12 "] {
            let raw = withFlatString(value) { data, length, byteCount, hash in
                __kk_string_toBigIntegerOrNull_flat(data, length, byteCount, hash)
            }
            #expect(raw == runtimeNullSentinelInt, "Expected \(value) to yield null")
        }
    }

    @Test
    func testBigIntegerAndHandlesPositiveOperands() throws {
        let lhs = try bigInteger("12")
        let rhs = try bigInteger("10")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "8")
    }

    @Test
    func testBigIntegerAndHandlesLargePositiveOperands() throws {
        let lhs = try bigInteger("18446744073709551615")
        let rhs = try bigInteger("255")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "255")
    }

    @Test
    func testBigIntegerAndUsesTwosComplementForNegativeOperands() throws {
        let negativeOne = try bigInteger("-1")
        let mask = try bigInteger("255")
        let result = kk_biginteger_and(negativeOne, mask)
        #expect(stringValue(__kk_biginteger_toString(result)) == "255")
    }

    @Test
    func testBigIntegerAndHandlesNegativeAndPositiveBits() throws {
        let lhs = try bigInteger("-2")
        let rhs = try bigInteger("3")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "2")
    }

    @Test
    func testBigIntegerAndHandlesZeroAndPositive() throws {
        let lhs = try bigInteger("0")
        let rhs = try bigInteger("123")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "0")
    }

    @Test
    func testBigIntegerAndHandlesPositiveAndZero() throws {
        let lhs = try bigInteger("456")
        let rhs = try bigInteger("0")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "0")
    }

    @Test
    func testBigIntegerAndHandlesZeroAndZero() throws {
        let lhs = try bigInteger("0")
        let rhs = try bigInteger("0")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "0")
    }

    @Test
    func testBigIntegerAndHandlesBothNegative() throws {
        let lhs = try bigInteger("-2")
        let rhs = try bigInteger("-3")
        let result = kk_biginteger_and(lhs, rhs)
        // -2 in two's complement: ...11111110
        // -3 in two's complement: ...11111101
        // AND:                 ...11111100 = -4
        #expect(stringValue(__kk_biginteger_toString(result)) == "-4")
    }

    @Test
    func testBigIntegerAndIdentityWithNegativeOne() throws {
        let lhs = try bigInteger("123")
        let rhs = try bigInteger("-1")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "123")
    }

    @Test
    func testBigIntegerAndIdentityWithNegativeOneReversed() throws {
        let lhs = try bigInteger("-1")
        let rhs = try bigInteger("456")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "456")
    }

    @Test
    func testBigIntegerAndSameOperands() throws {
        let value = try bigInteger("789")
        let result = kk_biginteger_and(value, value)
        #expect(stringValue(__kk_biginteger_toString(result)) == "789")
    }

    @Test
    func testBigIntegerAndSignBitBoundary() throws {
        // Number near Int64.MAX_VALUE
        let lhs = try bigInteger("9223372036854775807") // Int64.MAX_VALUE
        let rhs = try bigInteger("1")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "1")
    }

    @Test
    func testBigIntegerAndVeryLargeNumbers() throws {
        // Multi-byte sign extension scenario
        let lhs = try bigInteger("340282366920938463463374607431768211455") // 2^128 - 1
        let rhs = try bigInteger("18446744073709551615") // 2^64 - 1
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "18446744073709551615")
    }

    @Test
    func testBigIntegerAndNegativeWithZero() throws {
        let lhs = try bigInteger("-123")
        let rhs = try bigInteger("0")
        let result = kk_biginteger_and(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "0")
    }

    // MARK: - New BigInteger Function Tests

    @Test
    func testBigIntegerOrHandlesPositiveOperands() throws {
        let lhs = try bigInteger("12")  // 1100
        let rhs = try bigInteger("10")  // 1010
        let result = kk_biginteger_or(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "14") // 1110
    }

    @Test
    func testBigIntegerOrHandlesNegativeOperands() throws {
        let lhs = try bigInteger("-1")
        let rhs = try bigInteger("0")
        let result = kk_biginteger_or(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "-1")
    }

    @Test
    func testBigIntegerXorHandlesPositiveOperands() throws {
        let lhs = try bigInteger("12")  // 1100
        let rhs = try bigInteger("10")  // 1010
        let result = kk_biginteger_xor(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "6") // 0110
    }

    @Test
    func testBigIntegerXorHandlesNegativeOperands() throws {
        let lhs = try bigInteger("-1")
        let rhs = try bigInteger("0")
        let result = kk_biginteger_xor(lhs, rhs)
        #expect(stringValue(__kk_biginteger_toString(result)) == "-1")
    }

    @Test
    func testBigIntegerNotHandlesPositive() throws {
        let value = try bigInteger("0")
        let result = kk_biginteger_not(value)
        #expect(stringValue(__kk_biginteger_toString(result)) == "-1")
    }

    @Test
    func testBigIntegerNotHandlesNegative() throws {
        let value = try bigInteger("-1")
        let result = kk_biginteger_not(value)
        #expect(stringValue(__kk_biginteger_toString(result)) == "0")
    }

    @Test
    func testBigIntegerShiftLeft() throws {
        let value = try bigInteger("1")
        let result = kk_biginteger_shiftLeft(value, 3)
        #expect(stringValue(__kk_biginteger_toString(result)) == "8")
    }

    @Test
    func testBigIntegerShiftRight() throws {
        let value = try bigInteger("8")
        let result = kk_biginteger_shiftRight(value, 3)
        #expect(stringValue(__kk_biginteger_toString(result)) == "1")
    }

    @Test
    func testBigIntegerShiftRightNegative() throws {
        let value = try bigInteger("-8")
        let result = kk_biginteger_shiftRight(value, 1)
        #expect(stringValue(__kk_biginteger_toString(result)) == "-4")
    }

    // Regression coverage for a big-endian/little-endian mismatch in the
    // carry propagation: shiftLeft/shiftRight only exercised single-byte
    // magnitudes above, which masked the bug (e.g. BigInteger("100").shiftLeft(3)
    // produced 8195 instead of 800 because the generated carry byte landed on
    // the wrong side of the big-endian result).

    @Test
    func testBigIntegerShiftLeftCrossesByteBoundary() throws {
        let value = try bigInteger("100")
        let result = kk_biginteger_shiftLeft(value, 3)
        #expect(stringValue(__kk_biginteger_toString(result)) == "800")
    }

    @Test
    func testBigIntegerShiftLeftCrossesByteBoundaryNegative() throws {
        let value = try bigInteger("-100")
        let result = kk_biginteger_shiftLeft(value, 3)
        #expect(stringValue(__kk_biginteger_toString(result)) == "-800")
    }

    @Test
    func testBigIntegerShiftRightCrossesByteBoundary() throws {
        let value = try bigInteger("291")
        let result = kk_biginteger_shiftRight(value, 4)
        #expect(stringValue(__kk_biginteger_toString(result)) == "18")
    }

    @Test
    func testBigIntegerShiftRightCrossesByteBoundaryNegative() throws {
        let value = try bigInteger("-291")
        let result = kk_biginteger_shiftRight(value, 4)
        #expect(stringValue(__kk_biginteger_toString(result)) == "-19")
    }

    @Test
    func testBigIntegerShiftLeftLargeMagnitude() throws {
        let value = try bigInteger("12345678901234567890")
        let result = kk_biginteger_shiftLeft(value, 9)
        #expect(stringValue(__kk_biginteger_toString(result)) == "6320987597432098759680")
    }

    @Test
    func testBigIntegerShiftRightLargeMagnitude() throws {
        let value = try bigInteger("12345678901234567890")
        let result = kk_biginteger_shiftRight(value, 9)
        #expect(stringValue(__kk_biginteger_toString(result)) == "24112654103973765")
    }

    @Test
    func testBigIntegerModInverse() throws {
        let value = try bigInteger("3")
        let modulus = try bigInteger("11")
        var thrown = 0
        let result = kk_biginteger_modInverse(value, modulus, &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_biginteger_toString(result)) == "4") // 3 * 4 ≡ 1 (mod 11)
    }

    @Test
    func testBigIntegerModInverseNoInverse() throws {
        let value = try bigInteger("6")
        let modulus = try bigInteger("12")
        var thrown = 0
        _ = kk_biginteger_modInverse(value, modulus, &thrown)
        #expect(thrown != 0) // Should throw exception
    }

    @Test
    func testBigIntegerModInverseZeroModulus() throws {
        let value = try bigInteger("3")
        let modulus = try bigInteger("0")
        var thrown = 0
        _ = kk_biginteger_modInverse(value, modulus, &thrown)
        #expect(thrown != 0) // Should throw exception for zero modulus
    }

    @Test
    func testBigIntegerModPow() throws {
        let base = try bigInteger("3")
        let exponent = try bigInteger("4")
        let modulus = try bigInteger("7")
        var thrown = 0
        let result = kk_biginteger_modPow(base, exponent, modulus, &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_biginteger_toString(result)) == "4") // 3^4 = 81 ≡ 4 (mod 7)
    }

    @Test
    func testBigIntegerModPowZeroExponent() throws {
        let base = try bigInteger("3")
        let exponent = try bigInteger("0")
        let modulus = try bigInteger("7")
        var thrown = 0
        let result = kk_biginteger_modPow(base, exponent, modulus, &thrown)
        #expect(thrown == 0)
        #expect(stringValue(__kk_biginteger_toString(result)) == "1")
    }

    @Test
    func testBigIntegerToByteArray() throws {
        let value = try bigInteger("255")
        let result = kk_biginteger_toByteArray(value)
        // Should return [0xFF] for 255
        #expect(UnsafeMutableRawPointer(bitPattern: result) != nil)
        // Note: Full array verification would require additional runtime functions
    }

    @Test
    func testBigIntegerToByteArrayNegative() throws {
        let value = try bigInteger("-1")
        let result = kk_biginteger_toByteArray(value)
        // Should return [0xFF] for -1 in two's complement
        #expect(UnsafeMutableRawPointer(bitPattern: result) != nil)
        // Note: Full array verification would require additional runtime functions
    }
}
