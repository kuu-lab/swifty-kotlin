#if canImport(Testing)
@testable import Runtime
import Testing

/// Tests for the Base64 runtime ABI (STDLIB-031-ABI-001).
///
/// RFC 4648 test vectors are taken from §10 of the spec:
///   ""       → ""
///   "f"      → "Zg=="
///   "fo"     → "Zm8="
///   "foo"    → "Zm9v"
///   "foob"   → "Zm9vYg=="
///   "fooba"  → "Zm9vYmE="
///   "foobar" → "Zm9vYmFy"
@Suite
struct RuntimeBase64Tests {

    // MARK: - Helpers

    private func makeByteArray(_ bytes: [UInt8]) -> Int {
        let intElements = bytes.map { Int(Int8(bitPattern: $0)) }
        return registerRuntimeObject(RuntimeListBox(elements: intElements))
    }

    private func makeByteArrayFromString(_ s: String) -> Int {
        makeByteArray(Array(s.utf8))
    }

    private func runtimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else { return "" }
        return box.value
    }

    private func makeRuntimeString(_ s: String) -> Int {
        let utf8 = Array(s.utf8)
        if utf8.isEmpty {
            var nul: UInt8 = 0
            return Int(bitPattern: kk_string_from_utf8(&nul, 0))
        }
        return utf8.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return 0 }
            return Int(bitPattern: kk_string_from_utf8(base, Int32(buf.count)))
        }
    }

    private func byteArrayToUInt8s(_ raw: Int) -> [UInt8] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else { return [] }
        return box.elements.map { UInt8(truncatingIfNeeded: $0) }
    }

    // Padding option raw values (must match Base64PaddingOption in RuntimeBase64.swift)
    private let paddingPresent = 0
    private let paddingAbsent = 1
    private let paddingPresentOptional = 2
    private let paddingAbsentOptional = 3

    // MARK: - RFC 4648 §10 Test Vectors — Default (RFC 4648 §4)

    @Test
    func testRFC4648VectorsEncodeDefault() {
        let vectors: [(String, String)] = [
            ("", ""),
            ("f", "Zg=="),
            ("fo", "Zm8="),
            ("foo", "Zm9v"),
            ("foob", "Zm9vYg=="),
            ("fooba", "Zm9vYmE="),
            ("foobar", "Zm9vYmFy"),
        ]
        for (input, expected) in vectors {
            let rawBytes = makeByteArrayFromString(input)
            let result = runtimeString(kk_base64_encode_default(rawBytes, paddingPresent))
            #expect(result == expected, "Encoding '\(input)' failed")
        }
    }

    @Test
    func testRFC4648VectorsDecodeDefault() {
        let vectors: [(String, String)] = [
            ("", ""),
            ("Zg==", "f"),
            ("Zm8=", "fo"),
            ("Zm9v", "foo"),
            ("Zm9vYg==", "foob"),
            ("Zm9vYmE=", "fooba"),
            ("Zm9vYmFy", "foobar"),
        ]
        for (input, expected) in vectors {
            var thrown = 0
            let resultRaw = kk_base64_decode_default(makeRuntimeString(input), paddingPresentOptional, &thrown)
            #expect(thrown == 0, "Unexpected throw for input '\(input)'")
            let bytes = byteArrayToUInt8s(resultRaw)
            let decoded = String(bytes: bytes, encoding: .utf8) ?? ""
            #expect(decoded == expected, "Decoding '\(input)' failed")
        }
    }

    // MARK: - PaddingOption.PRESENT

    @Test
    func testPaddingPresentEncodesWithPad() {
        let raw = makeByteArrayFromString("fo")
        let result = runtimeString(kk_base64_encode_default(raw, paddingPresent))
        #expect(result == "Zm8=")
    }

    @Test
    func testPaddingPresentRejectsMissingPadding() {
        var thrown = 0
        _ = kk_base64_decode_default(makeRuntimeString("Zm8"), paddingPresent, &thrown)
        #expect(thrown != 0, "Should throw on missing padding when PRESENT")
    }

    // MARK: - PaddingOption.ABSENT

    @Test
    func testPaddingAbsentEncodesWithoutPad() {
        let raw = makeByteArrayFromString("fo")
        let result = runtimeString(kk_base64_encode_default(raw, paddingAbsent))
        #expect(result == "Zm8")
    }

    @Test
    func testPaddingAbsentRejectsPadding() {
        var thrown = 0
        _ = kk_base64_decode_default(makeRuntimeString("Zm8="), paddingAbsent, &thrown)
        #expect(thrown != 0, "Should throw on padding when ABSENT")
    }

    @Test
    func testPaddingAbsentDecodeRoundTrip() {
        let input = "foobar"
        let rawBytes = makeByteArrayFromString(input)
        let encoded = runtimeString(kk_base64_encode_default(rawBytes, paddingAbsent))
        #expect(!encoded.contains("="), "Should have no padding")

        var thrown = 0
        let decoded = byteArrayToUInt8s(kk_base64_decode_default(makeRuntimeString(encoded), paddingAbsent, &thrown))
        #expect(thrown == 0)
        #expect(String(bytes: decoded, encoding: .utf8) == input)
    }

    // MARK: - PaddingOption.PRESENT_OPTIONAL

    @Test
    func testPaddingPresentOptionalEncodeHasPad() {
        let raw = makeByteArrayFromString("fo")
        let result = runtimeString(kk_base64_encode_default(raw, paddingPresentOptional))
        #expect(result == "Zm8=")
    }

    @Test
    func testPaddingPresentOptionalDecodeAcceptsBothForms() {
        for padded in ["Zm8=", "Zm8"] {
            var thrown = 0
            let bytes = byteArrayToUInt8s(kk_base64_decode_default(makeRuntimeString(padded), paddingPresentOptional, &thrown))
            #expect(thrown == 0, "Should not throw for '\(padded)'")
            #expect(String(bytes: bytes, encoding: .utf8) == "fo")
        }
    }

    // MARK: - PaddingOption.ABSENT_OPTIONAL

    @Test
    func testPaddingAbsentOptionalEncodeNoPad() {
        let raw = makeByteArrayFromString("fo")
        let result = runtimeString(kk_base64_encode_default(raw, paddingAbsentOptional))
        #expect(result == "Zm8")
    }

    @Test
    func testPaddingAbsentOptionalDecodeAcceptsBothForms() {
        for padded in ["Zm8=", "Zm8"] {
            var thrown = 0
            let bytes = byteArrayToUInt8s(kk_base64_decode_default(makeRuntimeString(padded), paddingAbsentOptional, &thrown))
            #expect(thrown == 0, "Should not throw for '\(padded)'")
            #expect(String(bytes: bytes, encoding: .utf8) == "fo")
        }
    }

    // MARK: - URL-safe Alphabet (-_)

    @Test
    func testUrlSafeEncodeUsesUrlAlphabet() {
        // Produce a byte sequence that generates + and / in standard base64
        // 0xFB 0xEF 0xBE → "+/++" in standard, "-_-+" in url-safe (no pad for length 3)
        let bytes: [UInt8] = [0xFB, 0xEF, 0xBE]
        let raw = makeByteArray(bytes)
        let result = runtimeString(kk_base64_encode_urlsafe(raw, paddingAbsent))
        #expect(!result.contains("+"), "URL-safe must not contain '+'")
        #expect(!result.contains("/"), "URL-safe must not contain '/'")
        #expect(result.contains("-") || result.contains("_"), "URL-safe must use - or _")
    }

    @Test
    func testUrlSafePresentPaddingKeepsPad() {
        let raw = makeByteArrayFromString("foob")
        let result = runtimeString(kk_base64_encode_urlsafe(raw, paddingPresent))
        #expect(result == "Zm9vYg==")
    }

    @Test
    func testUrlSafeRoundTrip() {
        let input = "Hello, World! \u{1F30D}"
        let rawBytes = makeByteArrayFromString(input)
        let encoded = runtimeString(kk_base64_encode_urlsafe(rawBytes, paddingAbsentOptional))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))

        var thrown = 0
        let decoded = byteArrayToUInt8s(kk_base64_decode_urlsafe(makeRuntimeString(encoded), paddingAbsentOptional, &thrown))
        #expect(thrown == 0)
        #expect(String(bytes: decoded, encoding: .utf8) == input)
    }

    @Test
    func testUrlSafeDecodeRejectsStandardChars() {
        // "+" and "/" are not valid URL-safe alphabet characters
        var thrown = 0
        _ = kk_base64_decode_urlsafe(makeRuntimeString("Zm9v+w=="), paddingPresentOptional, &thrown)
        #expect(thrown != 0, "URL-safe decode should reject standard-alphabet '+'")
    }

    // MARK: - MIME (RFC 2045)

    @Test
    func testMimeEncodeInsertsCRLF() {
        // Use 60 bytes so the output exceeds 76 characters (80 base64 chars)
        let bytes = [UInt8](repeating: 0xAB, count: 60)
        let raw = makeByteArray(bytes)
        let result = runtimeString(kk_base64_encode_mime(raw, paddingPresent))
        #expect(result.contains("\r\n"), "MIME output must contain CRLF")
        let lines = result.components(separatedBy: "\r\n")
        for line in lines where !line.isEmpty {
            #expect(line.count <= 76, "MIME line must be <= 76 chars")
        }
    }

    @Test
    func testMimeDecodeToleratesWhitespace() {
        // Manually build a MIME-formatted string with CRLF
        let input = "Zm9v\r\nYmFy"
        var thrown = 0
        let decoded = byteArrayToUInt8s(kk_base64_decode_mime(makeRuntimeString(input), paddingPresentOptional, &thrown))
        #expect(thrown == 0)
        #expect(String(bytes: decoded, encoding: .utf8) == "foobar")
    }

    @Test
    func testMimeRoundTrip() {
        let input = String(repeating: "KSwiftK", count: 12)
        let rawBytes = makeByteArrayFromString(input)
        let encoded = runtimeString(kk_base64_encode_mime(rawBytes, paddingPresent))
        var thrown = 0
        let decoded = byteArrayToUInt8s(kk_base64_decode_mime(makeRuntimeString(encoded), paddingPresentOptional, &thrown))
        #expect(thrown == 0)
        #expect(String(bytes: decoded, encoding: .utf8) == input)
    }

    // MARK: - withPadding configured instances

    @Test
    func testWithPaddingDefaultInstanceOmitsPadding() {
        let instance = kk_base64_withPadding_default(paddingAbsent)
        let raw = makeByteArrayFromString("foob")
        let encoded = runtimeString(kk_base64_encode_instance(instance, raw))
        #expect(encoded == "Zm9vYg")

        var thrown = 0
        let decoded = byteArrayToUInt8s(
            kk_base64_decode_instance(instance, makeRuntimeString(encoded), &thrown)
        )
        #expect(thrown == 0)
        #expect(String(bytes: decoded, encoding: .utf8) == "foob")
    }

    @Test
    func testWithPaddingInstanceCanChangeExistingPaddingMode() {
        let absent = kk_base64_withPadding_default(paddingAbsent)
        let presentOptional = kk_base64_withPadding_instance(absent, paddingPresentOptional)
        let raw = makeByteArrayFromString("foob")
        let encoded = runtimeString(kk_base64_encode_instance(presentOptional, raw))
        #expect(encoded == "Zm9vYg==")
    }

    @Test
    func testWithPaddingUrlSafeInstancePreservesAlphabet() {
        let instance = kk_base64_withPadding_urlsafe(paddingAbsentOptional)
        let raw = makeByteArray([0xE0, 0xA0, 0xBE, 0x21])
        let encoded = runtimeString(kk_base64_encode_instance(instance, raw))
        #expect(encoded == "4KC-IQ")
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))

        var thrown = 0
        let decoded = byteArrayToUInt8s(
            kk_base64_decode_instance(instance, makeRuntimeString("4KC-IQ=="), &thrown)
        )
        #expect(thrown == 0)
        #expect(decoded == [0xE0, 0xA0, 0xBE, 0x21])
    }

    @Test
    func testWithPaddingMimeInstanceKeepsWhitespaceTolerance() {
        let instance = kk_base64_withPadding_mime(paddingAbsent)
        let raw = makeByteArrayFromString("foob")
        let encoded = runtimeString(kk_base64_encode_instance(instance, raw))
        #expect(encoded == "Zm9vYg")

        var thrown = 0
        let decoded = byteArrayToUInt8s(
            kk_base64_decode_instance(instance, makeRuntimeString("Zm9v\r\nYg"), &thrown)
        )
        #expect(thrown == 0)
        #expect(String(bytes: decoded, encoding: .utf8) == "foob")
    }

    // MARK: - encodeToByteArray

    @Test
    func testEncodeToByteArrayDefaultProducesAsciiBytes() {
        let raw = makeByteArrayFromString("foo")
        let result = byteArrayToUInt8s(kk_base64_encodeToByteArray_default(raw, paddingPresent))
        #expect(String(bytes: result, encoding: .utf8) == "Zm9v")
    }

    @Test
    func testEncodeToByteArrayUrlSafe() {
        let bytes: [UInt8] = [0xFB, 0xEF, 0xBE]
        let raw = makeByteArray(bytes)
        let result = byteArrayToUInt8s(kk_base64_encodeToByteArray_urlsafe(raw, paddingAbsent))
        #expect(!result.contains(UInt8(ascii: "+")))
        #expect(!result.contains(UInt8(ascii: "/")))
    }

    @Test
    func testEncodeToByteArrayMimeContainsCRLF() {
        let bytes = [UInt8](repeating: 0xCC, count: 60)
        let raw = makeByteArray(bytes)
        let result = byteArrayToUInt8s(kk_base64_encodeToByteArray_mime(raw, paddingPresent))
        let str = String(bytes: result, encoding: .utf8) ?? ""
        #expect(str.contains("\r\n"))
    }

    // MARK: - decodeFromByteArray

    @Test
    func testDecodeFromByteArrayDefaultRoundTrip() {
        let encoded = makeByteArrayFromString("Zm9v")
        var thrown = 0
        let result = byteArrayToUInt8s(kk_base64_decodeFromByteArray_default(encoded, paddingPresentOptional, &thrown))
        #expect(thrown == 0)
        #expect(String(bytes: result, encoding: .utf8) == "foo")
    }

    @Test
    func testDecodeFromByteArrayUrlSafeRoundTrip() {
        let encoded = makeByteArrayFromString("4KC-")
        var thrown = 0
        let result = byteArrayToUInt8s(kk_base64_decodeFromByteArray_urlsafe(encoded, paddingAbsentOptional, &thrown))
        #expect(thrown == 0)
        #expect(String(bytes: result, encoding: .utf8) == "\u{083E}")
    }

    @Test
    func testDecodeFromByteArrayMimeToleratesWhitespace() {
        let encoded = makeByteArrayFromString("Zm9v\r\nYmFy")
        var thrown = 0
        let result = byteArrayToUInt8s(kk_base64_decodeFromByteArray_mime(encoded, paddingPresentOptional, &thrown))
        #expect(thrown == 0)
        #expect(String(bytes: result, encoding: .utf8) == "foobar")
    }

    // MARK: - Error cases

    @Test
    func testDecodeInvalidCharacterThrows() {
        var thrown = 0
        _ = kk_base64_decode_default(makeRuntimeString("!!!@"), paddingPresentOptional, &thrown)
        #expect(thrown != 0, "Should throw on invalid base64 characters")
    }

    @Test
    func testDecodeEmptyStringReturnsEmptyByteArray() {
        var thrown = 0
        let result = byteArrayToUInt8s(kk_base64_decode_default(makeRuntimeString(""), paddingPresentOptional, &thrown))
        #expect(thrown == 0)
        #expect(result == [])
    }

    // MARK: - PaddingOption constant ABI

    @Test
    func testPaddingOptionConstantValues() {
        #expect(kk_base64_padding_present() == 0)
        #expect(kk_base64_padding_absent() == 1)
        #expect(kk_base64_padding_present_optional() == 2)
        #expect(kk_base64_padding_absent_optional() == 3)
    }
}
#endif
