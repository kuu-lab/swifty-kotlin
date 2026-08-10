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
            kk_locale_new_flat(data, length, byteCount, hash)
        }
    }

    private func makeLocale(language: String, country: String) -> Int {
        withFlatString(language) { languageData, languageLength, languageByteCount, languageHash in
            withFlatString(country) { countryData, countryLength, countryByteCount, countryHash in
                kk_locale_new_language_country_flat(
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
}
#endif
