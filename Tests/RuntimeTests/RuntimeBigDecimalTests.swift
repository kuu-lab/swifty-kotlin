@testable import Runtime
import XCTest

final class RuntimeBigDecimalTests: XCTestCase {
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

    func testStringToBigDecimalAcceptsScientificNotation() {
        var thrown = 0
        let raw = withFlatString("1.25e3") { data, length, byteCount, hash in
            kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_bignum_toString(raw)), "1.25e3")
    }

    func testStringToBigDecimalAcceptsDecimalPointEdgeForms() {
        for value in [".5", "1.", "-.25", "+12.0E-3"] {
            var thrown = 0
            let raw = withFlatString(value) { data, length, byteCount, hash in
                kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
            }
            XCTAssertEqual(thrown, 0, "Expected \(value) to parse as BigDecimal")
            XCTAssertEqual(stringValue(kk_bignum_toString(raw)), value)
        }
    }

    func testStringToBigDecimalRejectsWhitespaceWrappedInput() {
        var thrown = 0
        _ = withFlatString(" 12.5 ") { data, length, byteCount, hash in
            kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertNotEqual(thrown, 0)
    }

    func testStringToBigDecimalRejectsMalformedInputs() {
        for value in ["", ".", "+", "-", "1e", "1e+", "e10", "NaN"] {
            var thrown = 0
            _ = withFlatString(value) { data, length, byteCount, hash in
                kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
            }
            XCTAssertNotEqual(thrown, 0, "Expected \(value) to throw NumberFormatException")
        }
    }

    func testStringToBigDecimalOrNullAcceptsScientificNotation() {
        let raw = kk_string_toBigDecimalOrNull(runtimeString("+.5E-2"))
        XCTAssertNotEqual(raw, runtimeNullSentinelInt)
        XCTAssertEqual(stringValue(kk_bignum_toString(raw)), "+.5E-2")
    }

    func testStringToBigDecimalOrNullReturnsNullForInvalidInput() {
        XCTAssertEqual(kk_string_toBigDecimalOrNull(runtimeString("not-a-number")), runtimeNullSentinelInt)
        XCTAssertEqual(kk_string_toBigDecimalOrNull(runtimeString(" 12.5 ")), runtimeNullSentinelInt)
    }
}
