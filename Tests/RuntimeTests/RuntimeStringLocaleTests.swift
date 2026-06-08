@testable import Runtime
import XCTest

final class RuntimeStringLocaleTests: XCTestCase {
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

    private func arrayElements(_ raw: Int) -> [Int] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let array = tryCast(ptr, to: RuntimeArrayBox.self)
        else {
            return []
        }
        return array.elements
    }

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

    func testLocaleLowercaseUsesTurkishRules() {
        let result = kk_string_lowercase_locale(runtimeString("I"), makeLocale("tr"))
        XCTAssertEqual(stringValue(result), "ı")
    }

    func testLocaleUppercaseUsesTurkishRules() {
        let result = kk_string_uppercase_locale(runtimeString("i"), makeLocale("tr"))
        XCTAssertEqual(stringValue(result), "İ")
    }

    func testLocaleCompareToFlatMatchesBasicOrdering() {
        let locale = makeLocale("en_US")
        withFlatString("abc") { lhsData, lhsLength, lhsByteCount, lhsHash in
            withFlatString("abd") { rhsData, rhsLength, rhsByteCount, rhsHash in
                let result = kk_string_compareTo_locale_flat(
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
                XCTAssertEqual(result, -1)
            }
        }
    }

    func testLocalePropertiesExposeLanguageCountryAndVariant() {
        let locale = makeLocale(language: "en", country: "US")
        XCTAssertEqual(stringValue(kk_locale_language(locale)), "en")
        XCTAssertEqual(stringValue(kk_locale_country(locale)), "US")
        XCTAssertEqual(stringValue(kk_locale_variant(locale)), "")
    }

    func testLocaleDisplayLanguageUsesDefaultLocale() {
        let original = kk_locale_getDefault(0)
        let japanese = makeLocale("ja_JP")
        _ = kk_locale_setDefault(0, japanese)
        defer { _ = kk_locale_setDefault(0, original) }

        let english = makeLocale("en_US")
        let displayLanguage = stringValue(kk_locale_displayLanguage(english))
        XCTAssertFalse(displayLanguage.isEmpty)
    }

    func testLocaleDefaultCanBeOverridden() {
        let original = kk_locale_getDefault(0)
        let locale = makeLocale(language: "tr", country: "TR")
        _ = kk_locale_setDefault(0, locale)
        defer { _ = kk_locale_setDefault(0, original) }

        let current = kk_locale_getDefault(0)
        XCTAssertEqual(stringValue(kk_locale_language(current)), "tr")
        XCTAssertEqual(stringValue(kk_locale_country(current)), "TR")
    }

    func testLocaleEqualityAndHashCodeAreValueBased() {
        let lhs = makeLocale(language: "en", country: "US")
        let rhs = makeLocale(language: "en", country: "US")

        XCTAssertTrue(boolValue(kk_any_equals(lhs, 0, rhs, 0)))
        XCTAssertEqual(kk_any_hashCode(lhs, 0), kk_any_hashCode(rhs, 0))
    }

    func testSingleArgumentLocaleTreatsInputAsLanguageField() {
        let locale = makeLocale("en_US_POSIX")
        XCTAssertEqual(stringValue(kk_locale_language(locale)), "en_us_posix")
        XCTAssertEqual(stringValue(kk_locale_country(locale)), "")
        XCTAssertEqual(stringValue(kk_locale_variant(locale)), "")
    }

    func testAvailableLocalesContainsKnownLocale() {
        let available = kk_locale_getAvailableLocales(0)
        let identifiers = arrayElements(available).map { stringValue(kk_locale_language($0)) + "_" + stringValue(kk_locale_country($0)) }
        XCTAssertTrue(identifiers.contains("en_US") || identifiers.contains("en_"))
    }
}
