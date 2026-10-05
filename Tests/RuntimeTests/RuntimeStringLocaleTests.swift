#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeStringLocaleTests {
    private func boolValue(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeBoolBox.self)
        else {
            return false
        }
        return box.value
    }

    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = runtimeRegisterFlatString(
            value,
            outLength: &length,
            outByteCount: &byteCount,
            outHash: &hash
        )
        let constData = data.map { UnsafePointer($0) }
        return body(constData, length, byteCount, hash)
    }

    private func flatLocaleStringValue(
        _ value: String,
        locale: Int,
        using call: (
            UnsafePointer<UInt8>?,
            Int,
            Int,
            Int,
            Int,
            UnsafeMutablePointer<Int>?,
            UnsafeMutablePointer<Int>?,
            UnsafeMutablePointer<Int>?
        ) -> UnsafeMutablePointer<UInt8>?
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = call(data, length, byteCount, hash, locale, &outLength, &outByteCount, &outHash)
            return runtimeStringFromFlatFields(
                data: outData.map { UnsafePointer($0) },
                length: outLength,
                byteCount: outByteCount,
                hash: outHash
            )
        }
    }

    private func makeLocale(_ identifier: String) -> Int {
        withFlatString(identifier) { data, length, byteCount, hash in
            __kk_locale_new_flat(data, length, byteCount, hash)
        }
    }

    private func makeLocale(language: String, country: String) -> Int {
        withFlatString(language) { languageData, languageLength, languageByteCount, languageHash in
            withFlatString(country) { countryData, countryLength, countryByteCount, countryHash in
                __kk_locale_new_language_country_flat(
                    languageData,
                    languageLength,
                    languageByteCount,
                    languageHash,
                    countryData,
                    countryLength,
                    countryByteCount,
                    countryHash
                )
            }
        }
    }

    @Test
    func testLocaleLowercaseUsesTurkishRules() {
        let result = flatLocaleStringValue(
            "I",
            locale: makeLocale("tr"),
            using: __kk_lowercase_locale_flat
        )
        #expect(result == "ı")
    }

    @Test
    func testLocaleUppercaseUsesTurkishRules() {
        let result = flatLocaleStringValue(
            "i",
            locale: makeLocale("tr"),
            using: __kk_uppercase_locale_flat
        )
        #expect(result == "İ")
    }

    @Test
    func caseConversionPreservesUTF16Boundaries() {
        let cases: [(input: [UInt16], lower: [UInt16], upper: [UInt16])] = [
            ([], [], []),
            ([0], [0], [0]),
            ([0, 65, 98, 0], [0, 97, 98, 0], [0, 65, 66, 0]),
            ([65, 0, 0, 98], [97, 0, 0, 98], [65, 0, 0, 66]),
            ([65, 0xD83D, 98], [97, 0xD83D, 98], [65, 0xD83D, 66]),
            ([0xDC00, 65, 0xD800], [0xDC00, 97, 0xD800], [0xDC00, 65, 0xD800]),
            ([0xD800, 0, 0xDC00], [0xD800, 0, 0xDC00], [0xD800, 0, 0xDC00]),
            ([0xE800, 0xE000, 65], [0xE800, 0xE000, 97], [0xE800, 0xE000, 65]),
            ([0xDF, 0, 0x130], [0xDF, 0, 105, 0x307], [83, 83, 0, 0x130]),
            ([0x39F, 0x3A3, 0, 0x39F, 0x3A3], [0x3BF, 0x3C2, 0, 0x3BF, 0x3C2], [0x39F, 0x3A3, 0, 0x39F, 0x3A3]),
            ([0x39F, 0x3A3, 0xD800, 0x39F, 0x3A3], [0x3BF, 0x3C2, 0xD800, 0x3BF, 0x3C2], [0x39F, 0x3A3, 0xD800, 0x39F, 0x3A3]),
            ([65, 0x3A3, 0, 66], [97, 0x3C2, 0, 98], [65, 0x3A3, 0, 66]),
            ([65, 0, 0x3A3], [97, 0, 0x3C3], [65, 0, 0x3A3]),
            ([65, 0x3A3, 0xD800, 66], [97, 0x3C2, 0xD800, 98], [65, 0x3A3, 0xD800, 66]),
            ([65, 0xD800, 0x3A3], [97, 0xD800, 0x3C3], [65, 0xD800, 0x3A3]),
            // Deseret uppercase and lowercase letters form valid surrogate pairs.
            ([0xD801, 0xDC00, 0, 0xD801, 0xDC28], [0xD801, 0xDC28, 0, 0xD801, 0xDC28], [0xD801, 0xDC00, 0, 0xD801, 0xDC00]),
        ]
        let us = makeLocale(language: "en", country: "US")
        for testCase in cases {
            let source = runtimeKotlinStringFromUTF16CodeUnits(testCase.input)
            let raw = runtimeMakeStringRaw(source)
            #expect(runtimeStringUTF16CodeUnits(kk_string_lowercase(raw)) == testCase.lower)
            #expect(runtimeStringUTF16CodeUnits(kk_string_uppercase(raw)) == testCase.upper)
            for locale in [us, 0] {
                #expect(runtimeStringUTF16CodeUnits(__kk_lowercase_locale(raw, locale)) == testCase.lower)
                #expect(runtimeStringUTF16CodeUnits(__kk_uppercase_locale(raw, locale)) == testCase.upper)
                #expect(runtimeKotlinStringUTF16CodeUnits(flatLocaleStringValue(source, locale: locale, using: __kk_lowercase_locale_flat)) == testCase.lower)
                #expect(runtimeKotlinStringUTF16CodeUnits(flatLocaleStringValue(source, locale: locale, using: __kk_uppercase_locale_flat)) == testCase.upper)
            }
            let lowerFlat = flatLocaleStringValue(source, locale: 0) { data, length, byteCount, hash, _, outLength, outByteCount, outHash in
                kk_string_lowercase_flat(data, length, byteCount, hash, outLength, outByteCount, outHash)
            }
            let upperFlat = flatLocaleStringValue(source, locale: 0) { data, length, byteCount, hash, _, outLength, outByteCount, outHash in
                kk_string_uppercase_flat(data, length, byteCount, hash, outLength, outByteCount, outHash)
            }
            #expect(runtimeKotlinStringUTF16CodeUnits(lowerFlat) == testCase.lower)
            #expect(runtimeKotlinStringUTF16CodeUnits(upperFlat) == testCase.upper)
        }
    }

    @Test
    func localeCaseMappingKeepsContextWithinRuns() {
        let turkish = makeLocale("tr")
        let source = runtimeKotlinStringFromUTF16CodeUnits([0x49, 0x307, 0, 0xD800, 0x49, 0x307])
        let lower = flatLocaleStringValue(source, locale: turkish, using: __kk_lowercase_locale_flat)
        #expect(runtimeKotlinStringUTF16CodeUnits(lower) == [105, 0, 0xD800, 105])
        let upperSource = runtimeKotlinStringFromUTF16CodeUnits([105, 0, 0xDC00, 105])
        let upper = flatLocaleStringValue(upperSource, locale: turkish, using: __kk_uppercase_locale_flat)
        #expect(runtimeKotlinStringUTF16CodeUnits(upper) == [0x130, 0, 0xDC00, 0x130])
        let lithuanian = makeLocale("lt")
        let accented = runtimeKotlinStringFromUTF16CodeUnits([0x49, 0x301, 0, 0x49, 0x301])
        let accentedLower = flatLocaleStringValue(accented, locale: lithuanian, using: __kk_lowercase_locale_flat)
        #expect(runtimeKotlinStringUTF16CodeUnits(accentedLower) == [105, 0x307, 0x301, 0, 105, 0x307, 0x301])
    }

    @Test
    func testLocaleCompareToFlatMatchesBasicOrdering() {
        let locale = makeLocale("en_US")
        withFlatString("abc") { lhsData, lhsLength, lhsByteCount, lhsHash in
            withFlatString("abd") { rhsData, rhsLength, rhsByteCount, rhsHash in
                let result = __kk_string_compareTo_locale_flat(
                    lhsData,
                    lhsLength,
                    lhsByteCount,
                    lhsHash,
                    rhsData,
                    rhsLength,
                    rhsByteCount,
                    rhsHash,
                    locale
                )
                #expect(result == -1)
            }
        }
    }

    @Test
    func testLocaleEqualityAndHashCodeAreValueBased() {
        let lhs = makeLocale(language: "en", country: "US")
        let rhs = makeLocale(language: "en", country: "US")

        #expect(boolValue(kk_any_equals(lhs, 0, rhs, 0)))
        #expect(kk_any_hashCode(lhs, 0) == kk_any_hashCode(rhs, 0))
    }

    @Test(arguments: [
        ("en", "US", "en_US"),
        ("tr", "TR", "tr_TR"),
        ("EN", "us", "en_US"),
        ("en", "", "en"),
        ("", "us", "_US"),
        ("", "", ""),
        ("en_US", "gb", "en_us_GB"),
    ])
    func testLocaleToString(language: String, country: String, expected: String) {
        let locale = makeLocale(language: language, country: country)
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = __kk_locale_toString_flat(locale, &length, &byteCount, &hash)
        #expect(runtimeStringFromFlatFields(
            data: data.map { UnsafePointer($0) }, length: length, byteCount: byteCount, hash: hash
        ) == expected)
        #expect(length == expected.utf16.count)
        #expect(byteCount == expected.utf8.count)
        // Runtime-produced flat strings leave the cached hash unset.
        #expect(hash == 0)
        #expect(runtimeRenderAnyForPrint(locale) == expected)
        #expect(runtimeElementToString(locale) == expected)
    }

    @Test(arguments: [("EN", "en"), ("en_US", "en_us"), ("", "")])
    func testLanguageOnlyLocaleToString(language: String, expected: String) {
        #expect(runtimeElementToString(makeLocale(language)) == expected)
    }
}
#endif
