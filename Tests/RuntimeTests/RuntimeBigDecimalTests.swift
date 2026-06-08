@testable import Runtime
import XCTest

final class RuntimeBigDecimalTests: XCTestCase {
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
        let raw = withFlatString("1.25e3") { data, length, byteCount, hash in
            kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(kk_bignum_toString(raw)), "1.25e3")
    }

    func testStringToBigDecimalRejectsWhitespaceWrappedInput() {
        var thrown = 0
        _ = withFlatString(" 12.5 ") { data, length, byteCount, hash in
            kk_string_toBigDecimal_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertNotEqual(thrown, 0)
    }
}
