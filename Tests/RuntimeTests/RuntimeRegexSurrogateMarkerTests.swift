@testable import Runtime
import Testing

/// KUU-4590: isolated UTF-16 surrogates cannot be stored in a Swift string
/// (every NSString/String path repairs them to U+FFFD), so the regex runtime
/// encodes the ICU-domain subject and pattern with escape pairs. These tests
/// exercise the kk_regex public API over inputs containing isolated
/// surrogates and private-use scalars.
@Suite(.runtimeIsolation(.all))
struct RuntimeRegexSurrogateMarkerTests {
    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func kotlinString(_ units: [UInt16]) -> String {
        runtimeKotlinStringFromUTF16CodeUnits(units)
    }

    private func makeRegex(_ pattern: String) -> Int {
        withFlatString(pattern) { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
    }

    private func findAllValues(_ regexRaw: Int, units: [UInt16]) -> [String] {
        let matchesRaw = withFlatString(kotlinString(units)) { data, length, byteCount, hash in
            kk_regex_findAll_flat(regexRaw, data, length, byteCount, hash)
        }
        guard let ptr = UnsafeMutableRawPointer(bitPattern: matchesRaw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else { return [] }
        return box.elements.map { runtimeString(__kk_match_result_group_value($0, 0)) }
    }

    private func findFirst(_ regexRaw: Int, units: [UInt16]) -> Int {
        withFlatString(kotlinString(units)) { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }
    }

    @Test
    func surrogateCategoryMatchesIsolatedSurrogates() {
        let regex = makeRegex("\\p{Cs}")
        // "xa\uD800b\uDC00" — two isolated surrogates, index 2 and 4.
        let values = findAllValues(regex, units: [0x78, 0x61, 0xD800, 0x62, 0xDC00])
        #expect(values.count == 2)
        let regexNever = makeRegex("\\p{Cs}")
        // private-use scalars are not surrogates
        #expect(findAllValues(regexNever, units: [0x41, 0xE005, 0x42]).isEmpty)
    }

    @Test
    func surrogateClassRangeMatchesPairSequence() {
        let regex = makeRegex("[\\uD800-\\uDFFF]")
        let values = findAllValues(regex, units: [0x61, 0xD800, 0x62])
        #expect(values.count == 1)
    }

    @Test
    func otherCategoryCIncludesSurrogates() {
        let regex = makeRegex("\\p{C}")
        #expect(findAllValues(regex, units: [0xD800]).count == 1)
        #expect(findAllValues(regex, units: [0x61]).isEmpty)
    }


    @Test
    func surrogateBlocksMatchTheirHalves() {
        let high = makeRegex("\\p{InHigh Surrogates}")
        #expect(findAllValues(high, units: [0xD800, 0xDBFF]).count == 2)
        #expect(findAllValues(high, units: [0xDC00]).isEmpty)
        let low = makeRegex("\\p{InLow Surrogates}")
        #expect(findAllValues(low, units: [0xDC00, 0xDFFF]).count == 2)
        #expect(findAllValues(low, units: [0xD800]).isEmpty)
    }

    @Test
    func dotMatchesWholeSurrogateUnit() {
        let regex = makeRegex("a.b")
        // dot must consume exactly one source unit — the surrogate pair in
        // the encoded domain — so "a\uD800b" matches as a whole.
        let values = findAllValues(regex, units: [0x61, 0xD800, 0x62])
        #expect(values.count == 1)
        // A valid surrogate pair is one code point: `.` still matches it.
        #expect(findAllValues(regex, units: [0x61, 0xD800, 0xDC00, 0x62]).count == 1)
    }

    @Test
    func translationsAreMarkerAware() {
        #expect(translateJavaPatternForICU("\\p{InHigh Surrogates}") == "\\uE800[\\uE000-\\uE3FF]")
        #expect(translateJavaPatternForICU("\\p{Cs}") == "\\uE800[\\uE000-\\uE7FF]")
        #expect(translateJavaPatternForICU("[\\uD800-\\uDFFF]") == "(?:[\\uD800-\\uDFFF]|\\uE800[\\uE000-\\uE7FF])")
        #expect(translateJavaPatternForICU("\\p{C}") == "(?:[\\p{C}--[\\uE000-\\uE801]]|\\uE800[\\uE000-\\uE7FF]|\\uE801[\\uE000-\\uE801])")
    }

    @Test
    func groupRangesReportKotlinUTF16Offsets() {
        let regex = makeRegex("x(\\p{Cs})")
        let match = findFirst(regex, units: [0x78, 0xD800])
        #expect(match != runtimeNullSentinelInt)
        // group 1 = the surrogate at unit index 1..1.
        let start = __kk_match_result_group_start(match, 1)
        let end = __kk_match_result_group_end(match, 1)
        #expect(start == 1)
        #expect(end == 1)
    }

    @Test
    func negatedCsDoesNotMatchPrivatePairs() {
        let regex = makeRegex("\\P{Cs}")
        // private-use scalar \uE005: \P{Cs} must match it — and must match
        // its pair encoding as one unit, not two markers.
        #expect(findAllValues(regex, units: [0x61, 0xE005]).count == 2)
        #expect(findAllValues(regex, units: [0xD800]).isEmpty)
    }

    @Test
    func matchEntireAndReplaceWork() {
        let entire = makeRegex("x\\p{Cs}y")
        let matched = withFlatString(kotlinString([0x78, 0xD800, 0x79])) { data, length, byteCount, hash in
            kk_regex_matchEntire_flat(entire, data, length, byteCount, hash)
        }
        #expect(matched != runtimeNullSentinelInt)

        let replaceRegex = makeRegex("\\p{Cs}")
        let subjectRaw = runtimeMakeStringRaw(kotlinString([0x61, 0xD800, 0x62]))
        let templateRaw = runtimeMakeStringRaw("Z")
        var thrown = 0
        let replaced = kk_string_replace_regex(subjectRaw, replaceRegex, templateRaw, &thrown)
        #expect(thrown == 0)
        #expect(runtimeString(replaced) == "aZb")
    }
}
