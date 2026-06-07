@testable import Runtime
import XCTest

final class RuntimeStringNormalizationTests: XCTestCase {
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
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) throws -> T
    ) rethrows -> T {
        let bytes = Array(value.utf8)
        return try bytes.withUnsafeBufferPointer { buffer in
            let pointer = buffer.baseAddress
            let count = bytes.count
            return try body(pointer, value.count, count, value.hashValue)
        }
    }

    func testNormalizeNFCComposesDecomposedAccent() {
        let decomposed = "e\u{0301}"
        let result = kk_string_normalize(runtimeString(decomposed), kk_normalization_form_nfc())
        XCTAssertEqual(stringValue(result), "\u{00E9}")
    }

    func testNormalizeNFDDecomposesPrecomposedAccent() {
        let precomposed = "\u{00E9}"
        let result = kk_string_normalize(runtimeString(precomposed), kk_normalization_form_nfd())
        XCTAssertEqual(stringValue(result), "e\u{0301}")
    }

    func testNormalizeNFKCRewritesCompatibilityGlyph() {
        let source = "\u{FB01}"
        let result = kk_string_normalize(runtimeString(source), kk_normalization_form_nfkc())
        XCTAssertEqual(stringValue(result), "fi")
    }

    func testIsNormalizedDetectsCanonicalForm() {
        let decomposed = runtimeString("e\u{0301}")
        XCTAssertEqual(kk_string_isNormalized(decomposed, kk_normalization_form_nfc()), 0)

        let normalized = kk_string_normalize(decomposed, kk_normalization_form_nfc())
        XCTAssertEqual(kk_string_isNormalized(normalized, kk_normalization_form_nfc()), 1)
    }

    func testFlatIsNormalizedDetectsCanonicalForm() {
        withFlatString("e\u{0301}") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_isNormalized_flat(data, length, byteCount, hash, kk_normalization_form_nfc()),
                0
            )
        }
        withFlatString("\u{00E9}") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_isNormalized_flat(data, length, byteCount, hash, kk_normalization_form_nfc()),
                1
            )
        }
    }
}
