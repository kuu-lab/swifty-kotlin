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

    // KSP-717: form tags are the NormalizationForm.tag values assigned in
    // Stdlib/kotlin/text/StringNormalize.kt (NFC=0, NFD=1, NFKC=2, NFKD=3);
    // the __kk_normalization_form_nf* Swift wrappers that used to name them
    // are gone now that NormalizationForms is a plain Kotlin object.
    private static let nfcTag = 0
    private static let nfdTag = 1
    private static let nfkcTag = 2

    @Test
    func testNormalizeNFCComposesDecomposedAccent() {
        let decomposed = "e\u{0301}"
        #expect(normalizedFlatValue(decomposed, form: Self.nfcTag) == "\u{00E9}")
    }

    @Test
    func testNormalizeNFDDecomposesPrecomposedAccent() {
        let precomposed = "\u{00E9}"
        #expect(normalizedFlatValue(precomposed, form: Self.nfdTag) == "e\u{0301}")
    }

    @Test
    func testNormalizeNFKCRewritesCompatibilityGlyph() {
        let source = "\u{FB01}"
        #expect(normalizedFlatValue(source, form: Self.nfkcTag) == "fi")
    }

    @Test
    func testFlatIsNormalizedDetectsCanonicalForm() {
        withFlatString("e\u{0301}") { data, length, byteCount, hash in
            #expect(
                __kk_string_isNormalized_flat(data, length, byteCount, hash, Self.nfcTag) == 0
            )
        }
        withFlatString("\u{00E9}") { data, length, byteCount, hash in
            #expect(
                __kk_string_isNormalized_flat(data, length, byteCount, hash, Self.nfcTag) == 1
            )
        }
    }
}
#endif
