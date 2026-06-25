@testable import Runtime
import XCTest

final class RuntimeBigDecimalTests: XCTestCase {
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

    func testStringToBigDecimalAcceptsScientificNotation() {
        var thrown = 0
        let raw = kk_string_toBigDecimal(runtimeString("1.25e3"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_bignum_toString(raw)), "1.25e3")
    }

    func testStringToBigDecimalAcceptsDecimalPointEdgeForms() {
        for value in [".5", "1.", "-.25", "+12.0E-3"] {
            var thrown = 0
            let raw = kk_string_toBigDecimal(runtimeString(value), &thrown)
            XCTAssertEqual(thrown, 0, "Expected \(value) to parse as BigDecimal")
            XCTAssertEqual(stringValue(kk_bignum_toString(raw)), value)
        }
    }

    func testStringToBigDecimalRejectsWhitespaceWrappedInput() {
        var thrown = 0
        _ = kk_string_toBigDecimal(runtimeString(" 12.5 "), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testStringToBigDecimalRejectsMalformedInputs() {
        for value in ["", ".", "+", "-", "1e", "1e+", "e10", "NaN"] {
            var thrown = 0
            _ = kk_string_toBigDecimal(runtimeString(value), &thrown)
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
