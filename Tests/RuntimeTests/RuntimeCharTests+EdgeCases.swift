// STDLIB-003: Char API edge case coverage
// Tests surrogate boundaries, radix edge cases, category boundaries,
// and predicates on chars with no case mapping.

#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeCharEdgeCaseTests {

    // MARK: - Helpers

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    // KSP-661: isDigit/isLetter/isLetterOrDigit/isWhitespace/isDefined は bundled
    // Kotlin (kotlin.text.CharPredicates) へ移行済み。以下のヘルパは、残存する
    // Unicode カテゴリブリッジ (__kk_char_unicode_category) が移行後の Kotlin 実装
    // と同じ結果を生む序数を返すことを、これらの境界入力で検証するために、Kotlin
    // 側と同じ合成ロジックを再現する。
    private func bridgeIsLetter(_ value: Int) -> Int {
        let category = __kk_char_unicode_category(value)
        return kk_box_bool((category >= 1 && category <= 5) ? 1 : 0)
    }

    private func bridgeIsDigit(_ value: Int) -> Int {
        kk_box_bool(__kk_char_unicode_category(value) == 9 ? 1 : 0)
    }

    private func bridgeIsLetterOrDigit(_ value: Int) -> Int {
        kk_box_bool((boolValue(bridgeIsLetter(value)) || boolValue(bridgeIsDigit(value))) ? 1 : 0)
    }

    private func bridgeIsWhitespace(_ value: Int) -> Int {
        let category = __kk_char_unicode_category(value)
        if category == 12 || category == 13 || category == 14 {
            return kk_box_bool(1)
        }
        let isControlWhitespace = (0x09 ... 0x0D).contains(value) || (0x1C ... 0x1F).contains(value)
        return kk_box_bool(isControlWhitespace ? 1 : 0)
    }

    private func bridgeIsDefined(_ value: Int) -> Int {
        kk_box_bool(__kk_char_unicode_category(value) != 0 ? 1 : 0)
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
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

    // MARK: - Char.MIN_VALUE / MAX_VALUE boundaries
    // Kotlin Char.MIN_VALUE = '\u0000', Char.MAX_VALUE = '\uFFFF'

    @Test
    func testMinValueCodePoint() {
        // Char.MIN_VALUE is '\u0000' (NUL), code = 0
        #expect(kk_char_code(0) == 0)
    }

    @Test
    func testMaxValueCodePoint() {
        // Char.MAX_VALUE is '\uFFFF', code = 65535
        #expect(kk_char_code(0xFFFF) == 0xFFFF)
    }

    @Test
    func testNulCharIsNotLetter() {
        #expect(!boolValue(bridgeIsLetter(0)))
    }

    @Test
    func testNulCharIsNotDigit() {
        #expect(!boolValue(bridgeIsDigit(0)))
    }

    @Test
    func testNulCharIsNotWhitespace() {
        #expect(!boolValue(bridgeIsWhitespace(0)))
    }

    @Test
    func testDefinedAsciiChar() {
        #expect(boolValue(bridgeIsDefined(Int(("A" as UnicodeScalar).value))))
    }

    @Test
    func testUnassignedCodePointIsNotDefined() {
        #expect(!boolValue(bridgeIsDefined(0x0378)))
    }

    @Test
    func testSurrogateCodeUnitIsDefined() {
        #expect(boolValue(bridgeIsDefined(0xD800)))
    }

    @Test
    func testOutOfRangeCodePointIsNotDefined() {
        #expect(!boolValue(bridgeIsDefined(0x110000)))
    }

    @Test
    func testSupplementaryCodePointBoundaries() {
        #expect(!boolValue(kk_char_isSupplementaryCodePoint(0xFFFF)))
        #expect(boolValue(kk_char_isSupplementaryCodePoint(0x10000)))
        #expect(boolValue(kk_char_isSupplementaryCodePoint(0x10FFFF)))
        #expect(!boolValue(kk_char_isSupplementaryCodePoint(0x110000)))
    }

    @Test
    func testSurrogatePairBoundaries() {
        #expect(boolValue(kk_char_isSurrogatePair(0xD800, 0xDC00)))
        #expect(boolValue(kk_char_isSurrogatePair(0xDBFF, 0xDFFF)))
        #expect(!boolValue(kk_char_isSurrogatePair(0xD7FF, 0xDC00)))
        #expect(!boolValue(kk_char_isSurrogatePair(0xD800, 0xE000)))
        #expect(!boolValue(kk_char_isSurrogatePair(0xDC00, 0xD800)))
    }

    @Test
    func testToCharsReturnsSingleCharArrayForBmpCodePoint() throws {
        let arrayRaw = kk_char_toChars(0x0041)
        let array = try #require(runtimeArrayBox(from: arrayRaw))
        #expect(array.elements.count == 1)
        #expect(kk_unbox_char(array.elements[0]) == 0x0041)
    }

    @Test
    func testToCharsReturnsSurrogatePairForSupplementaryCodePoint() throws {
        let arrayRaw = kk_char_toChars(0x10000)
        let array = try #require(runtimeArrayBox(from: arrayRaw))
        #expect(array.elements.count == 2)
        #expect(kk_unbox_char(array.elements[0]) == 0xD800)
        #expect(kk_unbox_char(array.elements[1]) == 0xDC00)
    }

    @Test
    func testToCharsReturnsUpperSurrogatePairBoundary() throws {
        let arrayRaw = kk_char_toChars(0x10FFFF)
        let array = try #require(runtimeArrayBox(from: arrayRaw))
        #expect(array.elements.count == 2)
        #expect(kk_unbox_char(array.elements[0]) == 0xDBFF)
        #expect(kk_unbox_char(array.elements[1]) == 0xDFFF)
    }

    @Test
    func testToCodePointDoesNotValidateSurrogatePair() {
        #expect(kk_char_toCodePoint(0xD800, 0xDC00) == 0x10000)
        #expect(kk_char_toCodePoint(0xDBFF, 0xDFFF) == 0x10FFFF)
        #expect(kk_char_toCodePoint(0x0041, 0x0042) == -56_547_262)
    }

    // MARK: - Surrogate boundaries

    // High surrogate range: U+D800 - U+DBFF
    @Test
    func testHighSurrogateRangeLowerBound() {
        #expect(boolValue(kk_char_isHighSurrogate(0xD800)))
        #expect(boolValue(kk_char_isSurrogate(0xD800)))
        #expect(!boolValue(kk_char_isLowSurrogate(0xD800)))
    }

    @Test
    func testHighSurrogateRangeUpperBound() {
        #expect(boolValue(kk_char_isHighSurrogate(0xDBFF)))
        #expect(boolValue(kk_char_isSurrogate(0xDBFF)))
        #expect(!boolValue(kk_char_isLowSurrogate(0xDBFF)))
    }

    @Test
    func testJustBelowHighSurrogateIsNotSurrogate() {
        // U+D7FF is just below surrogate range
        #expect(!boolValue(kk_char_isSurrogate(0xD7FF)))
        #expect(!boolValue(kk_char_isHighSurrogate(0xD7FF)))
        #expect(!boolValue(kk_char_isLowSurrogate(0xD7FF)))
    }

    // Low surrogate range: U+DC00 - U+DFFF
    @Test
    func testLowSurrogateRangeLowerBound() {
        #expect(boolValue(kk_char_isLowSurrogate(0xDC00)))
        #expect(boolValue(kk_char_isSurrogate(0xDC00)))
        #expect(!boolValue(kk_char_isHighSurrogate(0xDC00)))
    }

    @Test
    func testLowSurrogateRangeUpperBound() {
        #expect(boolValue(kk_char_isLowSurrogate(0xDFFF)))
        #expect(boolValue(kk_char_isSurrogate(0xDFFF)))
        #expect(!boolValue(kk_char_isHighSurrogate(0xDFFF)))
    }

    @Test
    func testJustAboveLowSurrogateIsNotSurrogate() {
        // U+E000 is first private-use area character, just above surrogate range
        #expect(!boolValue(kk_char_isSurrogate(0xE000)))
        #expect(!boolValue(kk_char_isHighSurrogate(0xE000)))
        #expect(!boolValue(kk_char_isLowSurrogate(0xE000)))
    }

    @Test
    func testNonSurrogateAscii() {
        #expect(!boolValue(kk_char_isSurrogate(Int(("A" as UnicodeScalar).value))))
        #expect(!boolValue(kk_char_isHighSurrogate(Int(("A" as UnicodeScalar).value))))
        #expect(!boolValue(kk_char_isLowSurrogate(Int(("A" as UnicodeScalar).value))))
    }

    // MARK: - isUpperCase / isLowerCase on chars with no case mapping

    @Test
    func testDigitHasNoCase() {
        #expect(!boolValue(__kk_char_is_uppercase(Int(("5" as UnicodeScalar).value))))
        #expect(!boolValue(__kk_char_is_lowercase(Int(("5" as UnicodeScalar).value))))
    }

    @Test
    func testPunctuationHasNoCase() {
        #expect(!boolValue(__kk_char_is_uppercase(Int(("!" as UnicodeScalar).value))))
        #expect(!boolValue(__kk_char_is_lowercase(Int(("!" as UnicodeScalar).value))))
    }

    @Test
    func testSpaceHasNoCase() {
        #expect(!boolValue(__kk_char_is_uppercase(Int((" " as UnicodeScalar).value))))
        #expect(!boolValue(__kk_char_is_lowercase(Int((" " as UnicodeScalar).value))))
    }

    @Test
    func testUpperCaseAsciiLetter() {
        #expect(boolValue(__kk_char_is_uppercase(Int(("A" as UnicodeScalar).value))))
        #expect(!boolValue(__kk_char_is_lowercase(Int(("A" as UnicodeScalar).value))))
    }

    @Test
    func testLowerCaseAsciiLetter() {
        #expect(!boolValue(__kk_char_is_uppercase(Int(("a" as UnicodeScalar).value))))
        #expect(boolValue(__kk_char_is_lowercase(Int(("a" as UnicodeScalar).value))))
    }

    // MARK: - KSP-662: case mapping bridges on chars with no case mapping

    @Test
    func testUppercaseOfDigitIsIdentity() {
        // '5'.uppercase() returns "5" (unchanged)
        #expect(runtimeStringValue(__kk_char_uppercase_string(Int(("5" as UnicodeScalar).value))) == "5")
    }

    @Test
    func testLowercaseOfDigitIsIdentity() {
        #expect(runtimeStringValue(__kk_char_lowercase_string(Int(("5" as UnicodeScalar).value))) == "5")
    }

    @Test
    func testUppercaseOfPunctuationIsIdentity() {
        #expect(runtimeStringValue(__kk_char_uppercase_string(Int(("!" as UnicodeScalar).value))) == "!")
    }

    @Test
    func testLowercaseOfPunctuationIsIdentity() {
        #expect(runtimeStringValue(__kk_char_lowercase_string(Int(("!" as UnicodeScalar).value))) == "!")
    }

    @Test
    func testUppercaseAscii() {
        #expect(runtimeStringValue(__kk_char_uppercase_string(Int(("a" as UnicodeScalar).value))) == "A")
    }

    @Test
    func testUppercaseWithTurkishLocale() {
        let locale = makeLocale(language: "tr", country: "TR")
        let result = __kk_char_uppercase_locale(Int(("i" as UnicodeScalar).value), locale)
        #expect(runtimeStringValue(result) == "\u{0130}")
    }

    @Test
    func testLowercaseAscii() {
        #expect(runtimeStringValue(__kk_char_lowercase_string(Int(("A" as UnicodeScalar).value))) == "a")
    }

    @Test
    func testLowercaseWithTurkishLocale() {
        let locale = makeLocale(language: "tr", country: "TR")
        let result = __kk_char_lowercase_locale(Int(("I" as UnicodeScalar).value), locale)
        #expect(runtimeStringValue(result) == "\u{0131}")
    }

    // MARK: - titlecase edge cases

    @Test
    func testTitlecaseOfNormalLetter() {
        // 'a' titlecase is 'A'
        #expect(runtimeStringValue(__kk_char_titlecase_string(Int(("a" as UnicodeScalar).value))) == "A")
    }

    @Test
    func testTitlecaseOfDigitIsIdentity() {
        #expect(runtimeStringValue(__kk_char_titlecase_string(Int(("5" as UnicodeScalar).value))) == "5")
    }

    @Test
    func testTitlecaseLigatureDzWithCaron() {
        // U+01C6 'ǆ' (lowercase DZ with caron) -> U+01C5 'ǅ' (titlecase)
        let dz = 0x01C6
        #expect(runtimeStringValue(__kk_char_titlecase_string(dz)) == "ǅ")
    }

    @Test
    func testTitlecaseLigatureDzUpperCase() {
        // U+01C4 'Ǆ' (uppercase DZ with caron) -> U+01C5 'ǅ' (titlecase)
        let dzUpper = 0x01C4
        #expect(runtimeStringValue(__kk_char_titlecase_string(dzUpper)) == "ǅ")
    }

    // MARK: - isTitleCase

    @Test
    func testTitleCaseLigatureIsRecognized() {
        // U+01C5 'ǅ' is categorized as a titlecase letter
        #expect(boolValue(kk_char_isTitleCase(0x01C5)))
    }

    @Test
    func testUpperCaseLetterIsNotTitleCase() {
        #expect(!boolValue(kk_char_isTitleCase(Int(("A" as UnicodeScalar).value))))
    }

    // MARK: - KSP-662: __kk_char_digit_value (Kotlin applies the radix bound)

    @Test
    func testDigitValueBoundariesAscii() {
        #expect(__kk_char_digit_value(Int(("0" as UnicodeScalar).value)) == 0)
        #expect(__kk_char_digit_value(Int(("9" as UnicodeScalar).value)) == 9)
    }

    @Test
    func testDigitValueOfLetterIsAboveBase10Range() {
        // 'a' is invalid in radix 10 but its raw digit value is 10.
        #expect(__kk_char_digit_value(Int(("a" as UnicodeScalar).value)) == 10)
    }

    @Test
    func testDigitValueRejectsWhitespace() {
        #expect(__kk_char_digit_value(Int((" " as UnicodeScalar).value)) == -1)
    }

    @Test
    func testDigitValueRejectsPunctuation() {
        #expect(__kk_char_digit_value(Int(("!" as UnicodeScalar).value)) == -1)
    }

    // MARK: - code property

    @Test
    func testCodeReturnsUnicodeCodePoint() {
        #expect(kk_char_code(Int(("A" as UnicodeScalar).value)) == 65)
        #expect(kk_char_code(Int(("a" as UnicodeScalar).value)) == 97)
        #expect(kk_char_code(Int(("0" as UnicodeScalar).value)) == 48)
        #expect(kk_char_code(Int((" " as UnicodeScalar).value)) == 32)
    }

    // MARK: - directionality property

    @Test
    func testDirectionalityReturnsKotlinEnumOrdinals() {
        #expect(kk_char_directionality(Int(("A" as UnicodeScalar).value)) == 1)
        #expect(kk_char_directionality(0x05D0) == 2)
        #expect(kk_char_directionality(0x0627) == 3)
        #expect(kk_char_directionality(Int(("5" as UnicodeScalar).value)) == 4)
        #expect(kk_char_directionality(Int((" " as UnicodeScalar).value)) == 13)
    }

    // MARK: - isWhitespace edge cases

    @Test
    func testTabIsWhitespace() {
        #expect(boolValue(bridgeIsWhitespace(Int(("\t" as UnicodeScalar).value))))
    }

    @Test
    func testNewlineIsWhitespace() {
        #expect(boolValue(bridgeIsWhitespace(Int(("\n" as UnicodeScalar).value))))
    }

    @Test
    func testCarriageReturnIsWhitespace() {
        #expect(boolValue(bridgeIsWhitespace(Int(("\r" as UnicodeScalar).value))))
    }

    @Test
    func testNoBreakSpaceIsWhitespace() {
        // U+00A0 NO-BREAK SPACE — isWhitespace in Kotlin returns true
        #expect(boolValue(bridgeIsWhitespace(0x00A0)))
    }

    @Test
    func testUnitSeparatorIsWhitespace() {
        // U+001F is in Kotlin's CONTROL whitespace range.
        #expect(boolValue(bridgeIsWhitespace(0x001F)))
    }

    @Test
    func testNextLineIsNotWhitespace() {
        // U+0085 is whitespace in Unicode, but not in Kotlin's Char.isWhitespace().
        #expect(!boolValue(bridgeIsWhitespace(0x0085)))
    }

    @Test
    func testLetterIsNotWhitespace() {
        #expect(!boolValue(bridgeIsWhitespace(Int(("A" as UnicodeScalar).value))))
    }

    // MARK: - isLetterOrDigit

    @Test
    func testLetterOrDigitForLetter() {
        #expect(boolValue(bridgeIsLetterOrDigit(Int(("Z" as UnicodeScalar).value))))
    }

    @Test
    func testLetterOrDigitForDigit() {
        #expect(boolValue(bridgeIsLetterOrDigit(Int(("3" as UnicodeScalar).value))))
    }

    @Test
    func testLetterOrDigitForSpace() {
        #expect(!boolValue(bridgeIsLetterOrDigit(Int((" " as UnicodeScalar).value))))
    }

    @Test
    func testLetterOrDigitForUnicodeLetter() {
        // U+00E9 'é' is a letter
        #expect(boolValue(bridgeIsLetterOrDigit(0x00E9)))
    }

    // MARK: - category mapping

    @Test
    func testCategoryForUppercaseLetter() {
        // 'A' -> UPPERCASE_LETTER = 1
        #expect(kk_char_category(Int(("A" as UnicodeScalar).value)) == 1)
    }

    @Test
    func testCategoryForLowercaseLetter() {
        // 'a' -> LOWERCASE_LETTER = 2
        #expect(kk_char_category(Int(("a" as UnicodeScalar).value)) == 2)
    }

    @Test
    func testCategoryForDecimalDigit() {
        // '5' -> DECIMAL_DIGIT_NUMBER = 9
        #expect(kk_char_category(Int(("5" as UnicodeScalar).value)) == 9)
    }

    @Test
    func testCategoryForTitlecaseLetter() {
        // U+01C5 'ǅ' -> TITLECASE_LETTER = 3
        #expect(kk_char_category(0x01C5) == 3)
    }

    // MARK: - ASCII vs Unicode letter categorization

    @Test
    func testAsciiLetterIsLetter() {
        #expect(boolValue(bridgeIsLetter(Int(("a" as UnicodeScalar).value))))
        #expect(boolValue(bridgeIsLetter(Int(("Z" as UnicodeScalar).value))))
    }

    @Test
    func testUnicodeLetterIsLetter() {
        // U+00E9 'é'
        #expect(boolValue(bridgeIsLetter(0x00E9)))
        // U+4E2D '中' (CJK unified ideograph)
        #expect(boolValue(bridgeIsLetter(0x4E2D)))
    }

    @Test
    func testAsciiDigitIsNotLetter() {
        #expect(!boolValue(bridgeIsLetter(Int(("9" as UnicodeScalar).value))))
    }

    @Test
    func testSurrogateCharacterIsNotLetter() {
        // Surrogates are not valid Unicode scalars, so isLetter should be false
        #expect(!boolValue(bridgeIsLetter(0xD800)))
    }

    @Test
    func testSurrogateCharacterIsNotDigit() {
        #expect(!boolValue(bridgeIsDigit(0xD800)))
    }

    // MARK: - isIdentifierIgnorable

    @Test
    func testNulIsIdentifierIgnorable() {
        // U+0000 NUL is an ISO control char in the ignorable range
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x0000)))
    }

    @Test
    func testISOControlIgnorableRangeLowerBound() {
        // U+0001 is ignorable
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x0001)))
        // U+0008 is the last in the first ignorable range
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x0008)))
    }

    @Test
    func testTabIsNotIdentifierIgnorable() {
        // U+0009 TAB is whitespace, not ignorable
        #expect(!boolValue(kk_char_isIdentifierIgnorable(0x0009)))
    }

    @Test
    func testSecondISOControlIgnorableRange() {
        // U+000E .. U+001B
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x000E)))
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x001B)))
    }

    @Test
    func testDeleteIsIdentifierIgnorable() {
        // U+007F DEL
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x007F)))
    }

    @Test
    func testC1ControlRangeIsIdentifierIgnorable() {
        // U+0080..U+009F
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x0080)))
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x009F)))
    }

    @Test
    func testAsciiLetterIsNotIdentifierIgnorable() {
        #expect(!boolValue(kk_char_isIdentifierIgnorable(Int(("A" as UnicodeScalar).value))))
    }

    @Test
    func testSpaceIsNotIdentifierIgnorable() {
        #expect(!boolValue(kk_char_isIdentifierIgnorable(Int((" " as UnicodeScalar).value))))
    }

    @Test
    func testUnicodeFormatCharIsIdentifierIgnorable() {
        // U+00AD SOFT HYPHEN is category Cf (format)
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x00AD)))
    }

    @Test
    func testZeroWidthNonJoinerIsIdentifierIgnorable() {
        // U+200C ZERO WIDTH NON-JOINER, category Cf
        #expect(boolValue(kk_char_isIdentifierIgnorable(0x200C)))
    }

    @Test
    func testByteOrderMarkIsIdentifierIgnorable() {
        // U+FEFF BOM, category Cf
        #expect(boolValue(kk_char_isIdentifierIgnorable(0xFEFF)))
    }

    // MARK: - STDLIB-TEXT-PROP-010: isJavaIdentifierStart

    @Test
    func testIsJavaIdentifierStartForUppercaseLetter() {
        #expect(boolValue(kk_char_isJavaIdentifierStart(Int(("A" as UnicodeScalar).value))))
    }

    @Test
    func testIsJavaIdentifierStartForLowercaseLetter() {
        #expect(boolValue(kk_char_isJavaIdentifierStart(Int(("z" as UnicodeScalar).value))))
    }

    @Test
    func testIsJavaIdentifierStartForUnderscore() {
        // '_' is a connector punctuation (Pc) — valid Java identifier start
        #expect(boolValue(kk_char_isJavaIdentifierStart(Int(("_" as UnicodeScalar).value))))
    }

    @Test
    func testIsJavaIdentifierStartForDollarSign() {
        // '$' is a currency symbol (Sc) — valid Java identifier start
        #expect(boolValue(kk_char_isJavaIdentifierStart(Int(("$" as UnicodeScalar).value))))
    }

    @Test
    func testIsJavaIdentifierStartRejectsDigit() {
        #expect(!boolValue(kk_char_isJavaIdentifierStart(Int(("5" as UnicodeScalar).value))))
    }

    @Test
    func testIsJavaIdentifierStartRejectsSpace() {
        #expect(!boolValue(kk_char_isJavaIdentifierStart(Int((" " as UnicodeScalar).value))))
    }

    @Test
    func testIsJavaIdentifierStartRejectsPunctuation() {
        #expect(!boolValue(kk_char_isJavaIdentifierStart(Int(("!" as UnicodeScalar).value))))
    }

    @Test
    func testIsJavaIdentifierStartForUnicodeLetter() {
        // U+00E9 'é' is a lowercase letter — valid Java identifier start
        #expect(boolValue(kk_char_isJavaIdentifierStart(0x00E9)))
    }

    @Test
    func testIsJavaIdentifierStartForCjkIdeograph() {
        // U+4E2D '中' is an other letter — valid Java identifier start
        #expect(boolValue(kk_char_isJavaIdentifierStart(0x4E2D)))
    }

    // MARK: - isLetter must exclude combining marks (category M*)
    // Kotlin Char.isLetter() is true only for L* categories (Lu/Ll/Lt/Lm/Lo);
    // combining marks (Mn/Mc/Me) are NOT letters.

    @Test
    func testCombiningMarkIsNotLetter() {
        // U+0301 COMBINING ACUTE ACCENT (Mn)
        #expect(!boolValue(bridgeIsLetter(0x0301)))
        // U+0300 COMBINING GRAVE ACCENT (Mn)
        #expect(!boolValue(bridgeIsLetter(0x0300)))
        // U+0903 DEVANAGARI SIGN VISARGA (Mc, spacing combining mark)
        #expect(!boolValue(bridgeIsLetter(0x0903)))
        // U+20DD COMBINING ENCLOSING CIRCLE (Me)
        #expect(!boolValue(bridgeIsLetter(0x20DD)))
    }

    @Test
    func testCombiningMarkIsNotLetterOrDigit() {
        #expect(!boolValue(bridgeIsLetterOrDigit(0x0301)))
        #expect(!boolValue(bridgeIsLetterOrDigit(0x20DD)))
    }

    @Test
    func testModifierLetterIsLetter() {
        // U+02B0 MODIFIER LETTER SMALL H (Lm) is a letter.
        #expect(boolValue(bridgeIsLetter(0x02B0)))
    }

    @Test
    func testTitlecaseLetterIsLetter() {
        // U+01C5 'ǅ' (Lt) is a letter.
        #expect(boolValue(bridgeIsLetter(0x01C5)))
    }

    @Test
    func testLetterNumberIsNotLetter() {
        // U+2160 ROMAN NUMERAL ONE (Nl) is NOT a letter (it is a number).
        #expect(!boolValue(bridgeIsLetter(0x2160)))
    }

    // MARK: - isUpperCase / isLowerCase follow Unicode Uppercase/Lowercase
    // Kotlin: isUpperCase == (category Lu) || Other_Uppercase, and likewise for
    // lowercase. This differs from "Lu+Lt" / "Ll" letter sets.

    @Test
    func testTitlecaseLetterIsNeitherUpperNorLower() {
        // U+01C5 'ǅ' (Lt) — titlecase is not upper case nor lower case.
        #expect(!boolValue(__kk_char_is_uppercase(0x01C5)))
        #expect(!boolValue(__kk_char_is_lowercase(0x01C5)))
    }

    @Test
    func testRomanNumeralUpperLowerCase() {
        // U+2160 ROMAN NUMERAL ONE has Other_Uppercase -> isUpperCase true.
        #expect(boolValue(__kk_char_is_uppercase(0x2160)))
        #expect(!boolValue(__kk_char_is_lowercase(0x2160)))
        // U+2170 SMALL ROMAN NUMERAL ONE has Other_Lowercase -> isLowerCase true.
        #expect(boolValue(__kk_char_is_lowercase(0x2170)))
        #expect(!boolValue(__kk_char_is_uppercase(0x2170)))
    }

    @Test
    func testCircledLatinLettersUpperLowerCase() {
        // U+24B6 CIRCLED LATIN CAPITAL LETTER A has Other_Uppercase.
        #expect(boolValue(__kk_char_is_uppercase(0x24B6)))
        // U+24D0 CIRCLED LATIN SMALL LETTER A has Other_Lowercase.
        #expect(boolValue(__kk_char_is_lowercase(0x24D0)))
    }

    @Test
    func testModifierLetterIsLowerCase() {
        // U+02B0 MODIFIER LETTER SMALL H has Other_Lowercase -> isLowerCase true.
        #expect(boolValue(__kk_char_is_lowercase(0x02B0)))
        #expect(!boolValue(__kk_char_is_uppercase(0x02B0)))
    }

    @Test
    func testAsciiCaseClassificationUnaffected() {
        // Sanity: the common ASCII path is still correct after the fix.
        #expect(boolValue(__kk_char_is_uppercase(Int(("A" as UnicodeScalar).value))))
        #expect(!boolValue(__kk_char_is_lowercase(Int(("A" as UnicodeScalar).value))))
        #expect(boolValue(__kk_char_is_lowercase(Int(("z" as UnicodeScalar).value))))
        #expect(!boolValue(__kk_char_is_uppercase(Int(("z" as UnicodeScalar).value))))
    }
}
#endif
