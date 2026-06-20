@testable import Runtime
import XCTest

final class RuntimeBigIntegerTests: XCTestCase {
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

    private func bigInteger(_ text: String) -> Int {
        var thrown = 0
        let raw = kk_biginteger_fromString(runtimeString(text), &thrown)
        XCTAssertEqual(thrown, 0, "Expected \(text) to parse as BigInteger")
        return raw
    }

    func testStringToBigIntegerAcceptsSignedDigits() {
        var thrown = 0
        let raw = kk_string_toBigInteger(runtimeString("+00012345678901234567890"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_biginteger_toString(raw)), "12345678901234567890")
    }

    func testStringToBigIntegerReturnsBigIntegerBoxUsableByOperations() {
        var thrown = 0
        let lhs = kk_string_toBigInteger(runtimeString("12345678901234567890"), &thrown)
        XCTAssertEqual(thrown, 0)
        let rhs = bigInteger("10")
        let result = kk_biginteger_add(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "12345678901234567900")
    }

    func testStringToBigIntegerRejectsDecimalPoint() {
        var thrown = 0
        _ = kk_string_toBigInteger(runtimeString("12.5"), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testBigIntegerAndHandlesPositiveOperands() {
        let lhs = bigInteger("12")
        let rhs = bigInteger("10")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "8")
    }

    func testBigIntegerAndHandlesLargePositiveOperands() {
        let lhs = bigInteger("18446744073709551615")
        let rhs = bigInteger("255")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "255")
    }

    func testBigIntegerAndUsesTwosComplementForNegativeOperands() {
        let negativeOne = bigInteger("-1")
        let mask = bigInteger("255")
        let result = kk_biginteger_and(negativeOne, mask)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "255")
    }

    func testBigIntegerAndHandlesNegativeAndPositiveBits() {
        let lhs = bigInteger("-2")
        let rhs = bigInteger("3")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "2")
    }

    func testBigIntegerAndHandlesZeroAndPositive() {
        let lhs = bigInteger("0")
        let rhs = bigInteger("123")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "0")
    }

    func testBigIntegerAndHandlesPositiveAndZero() {
        let lhs = bigInteger("456")
        let rhs = bigInteger("0")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "0")
    }

    func testBigIntegerAndHandlesZeroAndZero() {
        let lhs = bigInteger("0")
        let rhs = bigInteger("0")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "0")
    }

    func testBigIntegerAndHandlesBothNegative() {
        let lhs = bigInteger("-2")
        let rhs = bigInteger("-3")
        let result = kk_biginteger_and(lhs, rhs)
        // -2 in two's complement: ...11111110
        // -3 in two's complement: ...11111101
        // AND:                 ...11111100 = -4
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "-4")
    }

    func testBigIntegerAndIdentityWithNegativeOne() {
        let lhs = bigInteger("123")
        let rhs = bigInteger("-1")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "123")
    }

    func testBigIntegerAndIdentityWithNegativeOneReversed() {
        let lhs = bigInteger("-1")
        let rhs = bigInteger("456")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "456")
    }

    func testBigIntegerAndSameOperands() {
        let value = bigInteger("789")
        let result = kk_biginteger_and(value, value)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "789")
    }

    func testBigIntegerAndSignBitBoundary() {
        // Number near Int64.MAX_VALUE
        let lhs = bigInteger("9223372036854775807") // Int64.MAX_VALUE
        let rhs = bigInteger("1")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "1")
    }

    func testBigIntegerAndVeryLargeNumbers() {
        // Multi-byte sign extension scenario
        let lhs = bigInteger("340282366920938463463374607431768211455") // 2^128 - 1
        let rhs = bigInteger("18446744073709551615") // 2^64 - 1
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "18446744073709551615")
    }

    func testBigIntegerAndNegativeWithZero() {
        let lhs = bigInteger("-123")
        let rhs = bigInteger("0")
        let result = kk_biginteger_and(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "0")
    }

    // MARK: - New BigInteger Function Tests

    func testBigIntegerOrHandlesPositiveOperands() {
        let lhs = bigInteger("12")  // 1100
        let rhs = bigInteger("10")  // 1010
        let result = kk_biginteger_or(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "14") // 1110
    }

    func testBigIntegerOrHandlesNegativeOperands() {
        let lhs = bigInteger("-1")
        let rhs = bigInteger("0")
        let result = kk_biginteger_or(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "-1")
    }

    func testBigIntegerXorHandlesPositiveOperands() {
        let lhs = bigInteger("12")  // 1100
        let rhs = bigInteger("10")  // 1010
        let result = kk_biginteger_xor(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "6") // 0110
    }

    func testBigIntegerXorHandlesNegativeOperands() {
        let lhs = bigInteger("-1")
        let rhs = bigInteger("0")
        let result = kk_biginteger_xor(lhs, rhs)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "-1")
    }

    func testBigIntegerNotHandlesPositive() {
        let value = bigInteger("0")
        let result = kk_biginteger_not(value)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "-1")
    }

    func testBigIntegerNotHandlesNegative() {
        let value = bigInteger("-1")
        let result = kk_biginteger_not(value)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "0")
    }

    func testBigIntegerShiftLeft() {
        let value = bigInteger("1")
        let result = kk_biginteger_shiftLeft(value, 3)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "8")
    }

    func testBigIntegerShiftRight() {
        let value = bigInteger("8")
        let result = kk_biginteger_shiftRight(value, 3)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "1")
    }

    func testBigIntegerShiftRightNegative() {
        let value = bigInteger("-8")
        let result = kk_biginteger_shiftRight(value, 1)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "-4")
    }

    func testBigIntegerModInverse() {
        let value = bigInteger("3")
        let modulus = bigInteger("11")
        var thrown = 0
        let result = kk_biginteger_modInverse(value, modulus, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "4") // 3 * 4 ≡ 1 (mod 11)
    }

    func testBigIntegerModInverseNoInverse() {
        let value = bigInteger("6")
        let modulus = bigInteger("12")
        var thrown = 0
        _ = kk_biginteger_modInverse(value, modulus, &thrown)
        XCTAssertNotEqual(thrown, 0) // Should throw exception
    }

    func testBigIntegerModInverseZeroModulus() {
        let value = bigInteger("3")
        let modulus = bigInteger("0")
        var thrown = 0
        _ = kk_biginteger_modInverse(value, modulus, &thrown)
        XCTAssertNotEqual(thrown, 0) // Should throw exception for zero modulus
    }

    func testBigIntegerModPow() {
        let base = bigInteger("3")
        let exponent = bigInteger("4")
        let modulus = bigInteger("7")
        var thrown = 0
        let result = kk_biginteger_modPow(base, exponent, modulus, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "4") // 3^4 = 81 ≡ 4 (mod 7)
    }

    func testBigIntegerModPowZeroExponent() {
        let base = bigInteger("3")
        let exponent = bigInteger("0")
        let modulus = bigInteger("7")
        var thrown = 0
        let result = kk_biginteger_modPow(base, exponent, modulus, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_biginteger_toString(result)), "1")
    }

    func testBigIntegerToByteArray() {
        let value = bigInteger("255")
        let result = kk_biginteger_toByteArray(value)
        // Should return [0xFF] for 255
        XCTAssertNotNil(result)
        // Note: Full array verification would require additional runtime functions
    }

    func testBigIntegerToByteArrayNegative() {
        let value = bigInteger("-1")
        let result = kk_biginteger_toByteArray(value)
        // Should return [0xFF] for -1 in two's complement
        XCTAssertNotNil(result)
        // Note: Full array verification would require additional runtime functions
    }
}
