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
        let raw = kk_string_toBigDecimal(runtimeString("1.25e3"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_bignum_toString(raw)), "1.25e3")
    }

    func testStringToBigDecimalRejectsWhitespaceWrappedInput() {
        var thrown = 0
        _ = kk_string_toBigDecimal(runtimeString(" 12.5 "), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testStringToBigDecimalFlatAcceptsScientificNotation() {
        var thrown = 0
        let raw = withFlatString("1.25e3") { data, length, byteCount, hash in
            kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_bignum_toString(raw)), "1.25e3")
    }

    func testStringToBigDecimalFlatRejectsWhitespaceWrappedInput() {
        var thrown = 0
        _ = withFlatString(" 12.5 ") { data, length, byteCount, hash in
            kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertNotEqual(thrown, 0)
    }
}
