#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeStringNormalizationTests {
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

    private func flatStringValue(data: UnsafeMutablePointer<UInt8>?, byteCount: Int) -> String {
        guard let data else { return "" }
        let buffer = UnsafeBufferPointer(start: UnsafePointer(data), count: byteCount)
        return String(decoding: buffer, as: UTF8.self)
    }

    private func normalizedFlatValue(_ value: String, form: Int) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let resultData = __kk_string_normalize_flat(
                data,
                length,
                byteCount,
                hash,
                form,
                &outLength,
                &outByteCount,
                &outHash
            )
            return flatStringValue(data: resultData, byteCount: outByteCount)
        }
    }

    @Test
    func testNormalizeNFCComposesDecomposedAccent() {
        let decomposed = "e\u{0301}"
        #expect(normalizedFlatValue(decomposed, form: __kk_normalization_form_nfc()) == "\u{00E9}")
    }

    @Test
    func testNormalizeNFDDecomposesPrecomposedAccent() {
        let precomposed = "\u{00E9}"
        #expect(normalizedFlatValue(precomposed, form: __kk_normalization_form_nfd()) == "e\u{0301}")
    }

    @Test
    func testNormalizeNFKCRewritesCompatibilityGlyph() {
        let source = "\u{FB01}"
        #expect(normalizedFlatValue(source, form: __kk_normalization_form_nfkc()) == "fi")
    }

    @Test
    func testFlatIsNormalizedDetectsCanonicalForm() {
        withFlatString("e\u{0301}") { data, length, byteCount, hash in
            #expect(
                __kk_string_isNormalized_flat(data, length, byteCount, hash, __kk_normalization_form_nfc()) == 0
            )
        }
        withFlatString("\u{00E9}") { data, length, byteCount, hash in
            #expect(
                __kk_string_isNormalized_flat(data, length, byteCount, hash, __kk_normalization_form_nfc()) == 1
            )
        }
    }
}
#endif
