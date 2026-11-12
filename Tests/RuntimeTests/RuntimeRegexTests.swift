@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.all))
struct RuntimeRegexTests {
    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func runtimeListStrings(_ raw: Int) -> [String] {
        runtimeListElements(raw).map(runtimeString)
    }

    private func runtimeListElements(_ raw: Int) -> [Int] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            return []
        }
        return box.elements
    }

    private func regexFind(_ regexRaw: Int, input: String) -> Int {
        withFlatString(input) { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }
    }

    private func matchValue(_ matchRaw: Int) -> String {
        runtimeString(__kk_match_result_group_value(matchRaw, 0))
    }

    private func matchGroupValues(_ matchRaw: Int) -> [String] {
        (0 ..< __kk_match_result_group_count(matchRaw)).map { index in
            runtimeString(__kk_match_result_group_value(matchRaw, index))
        }
    }

    private func matchGroupIndex(_ matchRaw: Int, name: String) -> Int {
        withFlatString(name) { data, length, byteCount, hash in
            __kk_match_result_group_index_of_name_flat(matchRaw, data, length, byteCount, hash)
        }
    }

    @Test
    func matchResultsRetainTheirNominalType() throws {
        let regex = withFlatString("a") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let first = regexFind(regex, input: "aa")
        let next = __kk_match_result_next(first)
        let entire = withFlatString("a") { data, length, byteCount, hash in
            kk_regex_matchEntire_flat(regex, data, length, byteCount, hash)
        }
        let all = withFlatString("aa") { data, length, byteCount, hash in
            kk_regex_findAll_flat(regex, data, length, byteCount, hash)
        }
        let elements = runtimeListElements(all)
        try #require(elements.count == 2)
        let expectedType = nominalTypeToken(for: "kotlin.text.MatchResult")
        let otherType = nominalTypeToken(for: "kotlin.text.Regex")
        for match in [first, next, entire] + elements {
            try #require(match != runtimeNullSentinelInt)
            #expect(kk_op_is(match, expectedType) == 1)
            #expect(kk_op_is(match, otherType) == 0)
            var thrown = 0
            #expect(kk_op_cast(match, expectedType, &thrown) == match)
            #expect(thrown == 0)
            #expect(matchValue(match) == "a")
        }
    }

    @Test
    func matchResultValueAndGroupValues() {
        let regexRaw = withFlatString("(ab)(cd)") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let matchRaw = withFlatString("zzabcdyy") { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }

        #expect(matchRaw != runtimeNullSentinelInt)
        #expect(matchValue(matchRaw) == "abcd")
        #expect(matchGroupValues(matchRaw) == ["abcd", "ab", "cd"])
    }

    // MARK: - STDLIB-TEXT-FN-105: String.toRegex / toRegex(option) / toRegex(options)

    @Test
    func stringToRegexCreatesEquivalentRegex() {
        let regexRaw = withFlatString("[a-z]+") { data, length, byteCount, hash in
            kk_string_toRegex_flat(data, length, byteCount, hash, nil)
        }
        #expect(regexRaw != runtimeNullSentinelInt)
        let patternBack = runtimeString(__kk_regex_pattern(regexRaw))
        #expect(patternBack == "[a-z]+")
    }

    @Test
    func stringToRegexMatchesSameAsRegexCreate() {
        let direct = withFlatString("ab+c") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let viaToRegex = withFlatString("ab+c") { data, length, byteCount, hash in
            kk_string_toRegex_flat(data, length, byteCount, hash, nil)
        }
        #expect(
            (regexFind(direct, input: "abbbc") == runtimeNullSentinelInt)
                == (regexFind(viaToRegex, input: "abbbc") == runtimeNullSentinelInt)
        )
    }

    @Test
    func stringToRegexWithOptionIgnoreCase() {
        // ordinal 0 = IGNORE_CASE
        let optionRaw = kk_box_int(0)
        let regexRaw = withFlatString("hello") { data, length, byteCount, hash in
            kk_regex_create_with_option_flat(data, length, byteCount, hash, optionRaw, nil)
        }
        #expect(regexRaw != runtimeNullSentinelInt)
        let matchRaw = regexFind(regexRaw, input: "say HELLO world")
        #expect(matchRaw != runtimeNullSentinelInt)
        #expect(matchValue(matchRaw) == "HELLO")
    }

    @Test
    func stringToRegexWithOptionPreservesPattern() {
        // ordinal 1 = MULTILINE
        let optionRaw = kk_box_int(1)
        let regexRaw = withFlatString("^foo") { data, length, byteCount, hash in
            kk_regex_create_with_option_flat(data, length, byteCount, hash, optionRaw, nil)
        }
        #expect(regexRaw != runtimeNullSentinelInt)
        #expect(runtimeString(__kk_regex_pattern(regexRaw)) == "^foo")
    }

    @Test
    func stringToRegexWithOptionsSetIgnoreCase() {
        // Set<RegexOption> with ordinal 0 = IGNORE_CASE
        let setRaw = registerRuntimeObject(RuntimeSetBox(elements: [kk_box_int(0)]))
        let regexRaw = withFlatString("world") { data, length, byteCount, hash in
            kk_regex_create_with_options_flat(data, length, byteCount, hash, setRaw, nil)
        }
        #expect(regexRaw != runtimeNullSentinelInt)
        let matchRaw = regexFind(regexRaw, input: "Hello WORLD!")
        #expect(matchRaw != runtimeNullSentinelInt)
        #expect(matchValue(matchRaw) == "WORLD")
    }

    @Test
    func stringToRegexWithEmptyOptionsSet() {
        let setRaw = registerRuntimeObject(RuntimeSetBox(elements: []))
        let regexRaw = withFlatString("[0-9]+") { data, length, byteCount, hash in
            kk_regex_create_with_options_flat(data, length, byteCount, hash, setRaw, nil)
        }
        #expect(regexRaw != runtimeNullSentinelInt)
        let matchRaw = regexFind(regexRaw, input: "abc123def")
        #expect(matchRaw != runtimeNullSentinelInt)
        #expect(matchValue(matchRaw) == "123")
    }

    @Test
    func matchGroupLookupByNameAndRange() {
        let regexRaw = withFlatString("(?<lhs>ab)(?<rhs>cd)") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let matchRaw = withFlatString("zzabcdyy") { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }
        let lhsIndex = matchGroupIndex(matchRaw, name: "lhs")
        let rhsIndex = matchGroupIndex(matchRaw, name: "rhs")

        #expect(lhsIndex == 1)
        #expect(rhsIndex == 2)
        #expect(matchGroupIndex(matchRaw, name: "missing") == -1)
        #expect(runtimeString(__kk_match_result_group_value(matchRaw, lhsIndex)) == "ab")
        #expect(runtimeString(__kk_match_result_group_value(matchRaw, rhsIndex)) == "cd")

        #expect(__kk_match_result_group_start(matchRaw, lhsIndex) == 2)
        #expect(__kk_match_result_group_end(matchRaw, lhsIndex) == 3)
        #expect(__kk_match_result_group_start(matchRaw, rhsIndex) == 4)
        #expect(__kk_match_result_group_end(matchRaw, rhsIndex) == 5)
    }

    @Test
    func matchGroupBridgesReportAbsentAndOutOfRangeGroups() {
        let regexRaw = withFlatString("(a)|(b)") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let matchRaw = regexFind(regexRaw, input: "a")

        #expect(__kk_match_result_group_count(matchRaw) == 3)
        #expect(__kk_match_result_group_start(matchRaw, 1) == 0)
        // Group 2 did not participate in the match: no position data.
        #expect(__kk_match_result_group_start(matchRaw, 2) == -1)
        #expect(__kk_match_result_group_start(matchRaw, 7) == -1)
        #expect(runtimeString(__kk_match_result_group_value(matchRaw, 7)) == "")
    }

    @Test
    func flatStringRegexRuntimeAPIsUseFlattenedStringFields() {
        let regexRaw = withFlatString("[a-z]+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }

        withFlatString("abc") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, regexRaw)) == 1)
        }
        withFlatString("abc123") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, regexRaw)) == 0)
        }
        withFlatString("123abc") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_contains_regex_flat(data, length, byteCount, hash, regexRaw)) == 1)
        }

        let fromToRegex = withFlatString("\\d+") { data, length, byteCount, hash in
            kk_string_toRegex_flat(data, length, byteCount, hash, nil)
        }
        #expect(runtimeString(__kk_regex_pattern(fromToRegex)) == "\\d+")

        let literalRegex = withFlatString("a.b") { data, length, byteCount, hash in
            // ordinal 2 = LITERAL
            kk_regex_create_with_option_flat(data, length, byteCount, hash, kk_box_int(2), nil)
        }
        withFlatString("a.b") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, literalRegex)) == 1)
        }
        withFlatString("axb") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, literalRegex)) == 0)
        }

        let ignoreCaseOptions = registerRuntimeObject(RuntimeSetBox(elements: [kk_box_int(0)]))
        let ignoreCaseRegex = withFlatString("[a-z]+") { data, length, byteCount, hash in
            kk_regex_create_with_options_flat(data, length, byteCount, hash, ignoreCaseOptions, nil)
        }
        withFlatString("HELLO") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, ignoreCaseRegex)) == 1)
        }
    }

    @Test
    func flatRegexReceiverRuntimeAPIsUseFlattenedInputFields() {
        let wordRegex = withFlatString("[a-z]+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }

        let findRaw = withFlatString("123abc456") { data, length, byteCount, hash in
            kk_regex_find_flat(wordRegex, data, length, byteCount, hash)
        }
        #expect(findRaw != runtimeNullSentinelInt)
        #expect(matchValue(findRaw) == "abc")

        let findAllRaw = withFlatString("ab12cd") { data, length, byteCount, hash in
            kk_regex_findAll_flat(wordRegex, data, length, byteCount, hash)
        }
        let findAllValues = runtimeListElements(findAllRaw).map { matchValue($0) }
        #expect(findAllValues == ["ab", "cd"])

        let commaRegex = withFlatString(",") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let splitRaw = withFlatString("a,b,c") { data, length, byteCount, hash in
            kk_string_split_regex_flat(data, length, byteCount, hash, commaRegex)
        }
        #expect(runtimeListStrings(splitRaw) == ["a", "b", "c"])

        let entireRaw = withFlatString("abc") { data, length, byteCount, hash in
            kk_regex_matchEntire_flat(wordRegex, data, length, byteCount, hash)
        }
        #expect(entireRaw != runtimeNullSentinelInt)
        let partialRaw = withFlatString("abc123") { data, length, byteCount, hash in
            kk_regex_matchEntire_flat(wordRegex, data, length, byteCount, hash)
        }
        #expect(partialRaw == runtimeNullSentinelInt)

        withFlatString("123abc") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_containsMatchIn_flat(wordRegex, data, length, byteCount, hash)) == 1)
        }
        withFlatString("abc") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(wordRegex, data, length, byteCount, hash)) == 1)
        }
        withFlatString("abc123") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(wordRegex, data, length, byteCount, hash)) == 0)
        }

        let literalRegex = withFlatString("a.b") { data, length, byteCount, hash in
            kk_regex_from_literal_flat(0, data, length, byteCount, hash)
        }
        withFlatString("a.b") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(literalRegex, data, length, byteCount, hash)) == 1)
        }
        withFlatString("axb") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(literalRegex, data, length, byteCount, hash)) == 0)
        }

        let namedRegex = withFlatString("(?<lhs>ab)(?<rhs>cd)") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let namedMatch = withFlatString("zzabcdyy") { data, length, byteCount, hash in
            kk_regex_find_flat(namedRegex, data, length, byteCount, hash)
        }
        let lhsIndex = matchGroupIndex(namedMatch, name: "lhs")
        #expect(lhsIndex == 1)
        #expect(runtimeString(__kk_match_result_group_value(namedMatch, lhsIndex)) == "ab")
    }

    @Test
    func emptyPatternFindsZeroWidthMatchesAtEveryIndex() {
        var thrown = 0
        let regexRaw = withFlatString("") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        #expect(regexRaw != 0)
        #expect(regexRaw != runtimeNullSentinelInt)
        #expect(runtimeString(__kk_regex_pattern(regexRaw)) == "")

        let findAllRaw = withFlatString("ab") { data, length, byteCount, hash in
            kk_regex_findAll_flat(regexRaw, data, length, byteCount, hash)
        }
        let matches = runtimeListElements(findAllRaw)
        #expect(matches.map(matchValue) == ["", "", ""])
        #expect(matches.map { __kk_match_result_group_start($0, 0) } == [0, 1, 2])

        withFlatString("") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(regexRaw, data, length, byteCount, hash)) == 1)
        }
        withFlatString("ab") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(regexRaw, data, length, byteCount, hash)) == 0)
            #expect(kk_unbox_bool(kk_regex_containsMatchIn_flat(regexRaw, data, length, byteCount, hash)) == 1)
        }
    }

    @Test
    func emptyPatternNextReachesFinalZeroWidthMatch() {
        var thrown = 0
        let regexRaw = withFlatString("") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)

        var matchRaw = regexFind(regexRaw, input: "ab")
        var starts: [Int] = []
        while matchRaw != runtimeNullSentinelInt && matchRaw != 0 {
            starts.append(__kk_match_result_group_start(matchRaw, 0))
            matchRaw = __kk_match_result_next(matchRaw)
        }
        #expect(starts == [0, 1, 2])
    }

    @Test
    func emptyPatternReplaceInsertsAtEveryIndex() {
        var thrown = 0
        let regexRaw = withFlatString("") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        let resultRaw = kk_string_replace_regex(makeStringRaw("ab"), regexRaw, makeStringRaw("-"), nil)
        #expect(runtimeString(resultRaw) == "-a-b-")
    }

    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
                Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
            }
        }
    }

    // KUU-648: fromLiteral keeps the original literal as `.pattern`, not the escaped matcher.
    @Test
    func fromLiteralPreservesOriginalPatternAndLiteralOption() {
        let literalRegex = withFlatString("a.b") { data, length, byteCount, hash in
            kk_regex_from_literal_flat(0, data, length, byteCount, hash)
        }
        #expect(runtimeString(__kk_regex_pattern(literalRegex)) == "a.b")
        // ordinal 2 = RegexOption.LITERAL; Kotlin fromLiteral is Regex(literal, LITERAL).
        #expect(__kk_regex_option_mask(literalRegex) & (1 << 2) != 0)

        withFlatString("a.b") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(literalRegex, data, length, byteCount, hash)) == 1)
        }
        withFlatString("axb") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(literalRegex, data, length, byteCount, hash)) == 0)
        }
    }

    // MARK: - KUU-635: empty pattern

    @Test
    func emptyPatternMatchesEmptyStringEverywhere() {
        var thrown = 0
        let regexRaw = withFlatString("") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        #expect(regexRaw != 0)
        #expect(runtimeString(__kk_regex_pattern(regexRaw)) == "")

        withFlatString("") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(regexRaw, data, length, byteCount, hash)) == 1)
        }
        withFlatString("abc") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_matches_flat(regexRaw, data, length, byteCount, hash)) == 0)
        }

        let findAllRaw = withFlatString("ab") { data, length, byteCount, hash in
            kk_regex_findAll_flat(regexRaw, data, length, byteCount, hash)
        }
        let findAll = runtimeListElements(findAllRaw)
        #expect(findAll.count == 3)
        #expect(findAll.map { __kk_match_result_group_start($0, 0) } == [0, 1, 2])
        #expect(findAll.map { __kk_match_result_group_end($0, 0) } == [-1, 0, 1])

        let splitRaw = withFlatString("ab") { data, length, byteCount, hash in
            kk_string_split_regex_flat(data, length, byteCount, hash, regexRaw)
        }
        #expect(runtimeListStrings(splitRaw) == ["", "a", "b", ""])

        let literalRegex = withFlatString("") { data, length, byteCount, hash in
            kk_regex_from_literal_flat(0, data, length, byteCount, hash)
        }
        withFlatString("ab") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_regex_containsMatchIn_flat(literalRegex, data, length, byteCount, hash)) == 1)
        }
    }

    // MARK: - KUU-2772: java.util.regex-only inline flags (?u) / (?U)

    @Test
    func stripJavaOnlyInlineFlagsRemovesUnicodeFlags() {
        #expect(stripJavaOnlyInlineFlags("(?U)abc") == "abc")
        #expect(stripJavaOnlyInlineFlags("(?u)abc") == "abc")
        #expect(stripJavaOnlyInlineFlags("(?iU)abc") == "(?i)abc")
        #expect(stripJavaOnlyInlineFlags("(?U-i)abc") == "(?-i)abc")
        #expect(stripJavaOnlyInlineFlags("a(?U:b)c") == "a(?:b)c")
        #expect(stripJavaOnlyInlineFlags("(?imsx)abc") == "(?imsx)abc")
    }

    @Test
    func stripJavaOnlyInlineFlagsLeavesEscapesAndClassesAlone() {
        #expect(stripJavaOnlyInlineFlags("\\(?U)") == "\\(?U)")
        #expect(stripJavaOnlyInlineFlags("\\Q(?U)\\E(?U)x") == "\\Q(?U)\\Ex")
        #expect(stripJavaOnlyInlineFlags("[(?U)]") == "[(?U)]")
        #expect(stripJavaOnlyInlineFlags("(?<n>a)(?=b)(?:c)") == "(?<n>a)(?=b)(?:c)")
    }

    @Test
    func unicodeCharacterClassInlineFlagCompilesAndMatches() {
        var thrown = 0
        let regexRaw = withFlatString("(?U)abc") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        #expect(regexRaw != 0)
        let matchRaw = regexFind(regexRaw, input: "zabc")
        #expect(matchRaw != runtimeNullSentinelInt)
        #expect(matchValue(matchRaw) == "abc")
        #expect(runtimeString(__kk_regex_pattern(regexRaw)) == "(?U)abc")
    }

    // MARK: - KUU-4073: JVM default ASCII predefined classes

    @Test
    func translateRewritesPredefinedClassesToAsciiByDefault() {
        #expect(translateJavaPatternForICU("\\w+") == "[a-zA-Z0-9_]+")
        #expect(translateJavaPatternForICU("\\W+") == "[^a-zA-Z0-9_]+")
        #expect(translateJavaPatternForICU("\\d+") == "[0-9]+")
        #expect(translateJavaPatternForICU("\\D+") == "[^0-9]+")
        #expect(translateJavaPatternForICU("\\s+") == "[ \\t\\n\\x0B\\f\\r]+")
        #expect(translateJavaPatternForICU("\\S+") == "[^ \\t\\n\\x0B\\f\\r]+")
        // Inside classes the expansions are emitted as nested classes so they
        // union with neighbours instead of merging into a range.
        #expect(translateJavaPatternForICU("[\\w-]") == "[[a-zA-Z0-9_]-]")
        #expect(translateJavaPatternForICU("[^\\w]") == "[^[a-zA-Z0-9_]]")
        #expect(translateJavaPatternForICU("[\\W]") == "[[^a-zA-Z0-9_]]")
        // Escaped backslash + 'w' is not a class escape.
        #expect(translateJavaPatternForICU("\\\\w") == "\\\\w")
        // \Q...\E quoting is untouched.
        #expect(translateJavaPatternForICU("\\Q\\w\\E\\w") == "\\Q\\w\\E[a-zA-Z0-9_]")
    }

    @Test
    func translateKeepsUnicodeClassesInsideUnicodeFlagScopes() {
        #expect(translateJavaPatternForICU("(?U)\\w+") == "\\w+")
        #expect(translateJavaPatternForICU("(?U:\\w+)\\w") == "(?:\\w+)[a-zA-Z0-9_]")
        #expect(translateJavaPatternForICU("(?U)\\w(?-U)\\w") == "\\w[a-zA-Z0-9_]")
        #expect(translateJavaPatternForICU("(?iU)\\w") == "(?i)\\w")
        // A bare (?U) applies only until the end of the enclosing group.
        #expect(translateJavaPatternForICU("(a(?U)\\w)\\w") == "(a\\w)[a-zA-Z0-9_]")
        // Lookarounds/named groups open groups too and restore the mode on ')'.
        #expect(translateJavaPatternForICU("(?=(?U)\\w)\\w") == "(?=\\w)[a-zA-Z0-9_]")
    }

    @Test
    func asciiWordBoundaryMatchesJvmPositions() {
        let regexRaw = withFlatString("\\b") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let findAllRaw = withFlatString("Kästner") { data, length, byteCount, hash in
            kk_regex_findAll_flat(regexRaw, data, length, byteCount, hash)
        }
        let starts = runtimeListElements(findAllRaw).map { __kk_match_result_group_start($0, 0) }
        // JVM Pattern.compile("\\b") boundary positions on "Kästner".
        #expect(starts == [0, 1, 2, 7])
    }

    @Test
    func asciiPredefinedClassesMatchJvmDefaults() {
        let wordRaw = withFlatString("\\w+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let first = regexFind(wordRaw, input: "Kästner")
        #expect(first != runtimeNullSentinelInt)
        #expect(matchValue(first) == "K")

        let digitRaw = withFlatString("\\d+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let digitMatch = regexFind(digitRaw, input: "١٢٣45")
        #expect(digitMatch != runtimeNullSentinelInt)
        #expect(matchValue(digitMatch) == "45")
    }

    @Test
    func unicodeCharacterClassFlagRestoresUnicodeSemantics() {
        let wordRaw = withFlatString("(?U)\\w+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let first = regexFind(wordRaw, input: "Kästner")
        #expect(first != runtimeNullSentinelInt)
        #expect(matchValue(first) == "Kästner")
        #expect(runtimeString(__kk_regex_pattern(wordRaw)) == "(?U)\\w+")
    }

    // MARK: - KUU-4148: JVM default ASCII POSIX classes

    @Test
    func translateRewritesPosixClassesToAsciiByDefault() {
        #expect(translateJavaPatternForICU("\\p{Lower}+") == "[a-z]+")
        #expect(translateJavaPatternForICU("\\p{Upper}+") == "[A-Z]+")
        #expect(translateJavaPatternForICU("\\p{ASCII}+") == "[\\x00-\\x7F]+")
        #expect(translateJavaPatternForICU("\\p{Alpha}+") == "[a-zA-Z]+")
        #expect(translateJavaPatternForICU("\\p{Digit}+") == "[0-9]+")
        #expect(translateJavaPatternForICU("\\p{Alnum}+") == "[a-zA-Z0-9]+")
        #expect(translateJavaPatternForICU("\\p{Punct}+")
            == "[\\x21-\\x2F\\x3A-\\x40\\x5B-\\x60\\x7B-\\x7E]+")
        #expect(translateJavaPatternForICU("\\p{Graph}+") == "[\\x21-\\x7E]+")
        #expect(translateJavaPatternForICU("\\p{Print}+") == "[\\x20-\\x7E]+")
        #expect(translateJavaPatternForICU("\\p{Blank}+") == "[ \\t]+")
        #expect(translateJavaPatternForICU("\\p{Cntrl}+") == "[\\x00-\\x1F\\x7F]+")
        #expect(translateJavaPatternForICU("\\p{XDigit}+") == "[0-9a-fA-F]+")
        #expect(translateJavaPatternForICU("\\p{Space}+") == "[ \\t\\n\\x0B\\f\\r]+")
        // \P{Name} complements the ASCII expansion.
        #expect(translateJavaPatternForICU("\\P{Lower}+") == "[^a-z]+")
        #expect(translateJavaPatternForICU("\\P{XDigit}") == "[^0-9a-fA-F]")
        // Inside classes the expansion is a nested class so it unions safely.
        #expect(translateJavaPatternForICU("[\\p{Lower}_]") == "[[a-z]_]")
        #expect(translateJavaPatternForICU("[\\P{Lower}]") == "[[^a-z]]")
        #expect(translateJavaPatternForICU("[^\\p{Punct}]")
            == "[^[\\x21-\\x2F\\x3A-\\x40\\x5B-\\x60\\x7B-\\x7E]]")
        // Non-POSIX \p{...} names are Unicode on both sides: verbatim.
        #expect(translateJavaPatternForICU("\\p{Lu}+") == "\\p{Lu}+")
        #expect(translateJavaPatternForICU("\\p{InGreek}+") == "\\p{InGreek}+")
        // Names are case-sensitive like the JVM's (`\p{lower}` is an error
        // there; it is not rewritten here either).
        #expect(translateJavaPatternForICU("\\p{lower}+") == "\\p{lower}+")
        // Unbraced single-letter categories (exactly L M N P S Z C on the
        // JVM) are wrapped in braces for ICU; other letters stay verbatim.
        #expect(translateJavaPatternForICU("\\pL+") == "\\p{L}+")
        #expect(translateJavaPatternForICU("\\pC") == "\\p{C}")
        #expect(translateJavaPatternForICU("\\PL") == "\\P{L}")
        #expect(translateJavaPatternForICU("\\pU") == "\\pU")
        // \Q...\E quoting is untouched.
        #expect(translateJavaPatternForICU("\\Q\\p{Lower}\\E\\p{Lower}")
            == "\\Q\\p{Lower}\\E[a-z]")
    }

    @Test
    func translateKeepsPosixClassesUnicodeInsideUnicodeFlagScopes() {
        #expect(translateJavaPatternForICU("(?U)\\p{Lower}+") == "\\p{Lower}+")
        #expect(translateJavaPatternForICU("(?U:\\p{Lower}+)\\p{Lower}")
            == "(?:\\p{Lower}+)[a-z]")
        #expect(translateJavaPatternForICU("(?U)\\p{Lower}(?-U)\\p{Lower}")
            == "\\p{Lower}[a-z]")
        #expect(translateJavaPatternForICU("(?U)\\P{Lower}") == "\\P{Lower}")
        // A bare (?U) applies only until the end of the enclosing group.
        #expect(translateJavaPatternForICU("(x(?U)\\p{Lower}) \\p{Lower}")
            == "(x\\p{Lower}) [a-z]")
    }

    @Test
    func translateNeutralizesIcuSetOperatorsForJvmLiterals() {
        // `[:`, `[.`, `[=` are ICU set operators; the JVM reads the inner `[`
        // as an ordinary nested class of literal members, in both modes.
        #expect(translateJavaPatternForICU("[[:alpha:]]") == "[[\\:alpha:]]")
        #expect(translateJavaPatternForICU("[^[:alpha:]0-9]") == "[^[\\:alpha:]0-9]")
        #expect(translateJavaPatternForICU("[[:^alpha:]]") == "[[\\:^alpha:]]")
        #expect(translateJavaPatternForICU("(?U)[[:alpha:]]") == "[[\\:alpha:]]")
        #expect(translateJavaPatternForICU("[[=a=]]") == "[[\\=a=]]")
        #expect(translateJavaPatternForICU("[[.a.]]") == "[[\\.a.]]")
        #expect(translateJavaPatternForICU("[x[:digit:]y]") == "[x[\\:digit:]y]")
        // A plain `[` opens a nested class in both dialects; no escape added.
        #expect(translateJavaPatternForICU("[a[b]c]") == "[a[b]c]")
    }

    @Test
    func asciiPosixClassesMatchJvmDefaults() {
        let lowerRaw = withFlatString("\\p{Lower}+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let first = regexFind(lowerRaw, input: "AbCäü")
        #expect(first != runtimeNullSentinelInt)
        #expect(matchValue(first) == "b")

        let punctRaw = withFlatString("\\P{Punct}+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let punctMatch = regexFind(punctRaw, input: "«»!")
        #expect(punctMatch != runtimeNullSentinelInt)
        #expect(matchValue(punctMatch) == "«»")
    }

    @Test
    func posixBracketOperatorsMatchJvmLiterals() {
        // JVM reads [[:alpha:]] as a nested class of the literal characters
        // `:alpha:` — ':' matches but 'A' and 'ä' do not.
        let posixRaw = withFlatString("[[:alpha:]]+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let findAllRaw = withFlatString("AbCäü:") { data, length, byteCount, hash in
            kk_regex_findAll_flat(posixRaw, data, length, byteCount, hash)
        }
        #expect(runtimeListElements(findAllRaw).map(matchValue) == [":"])

        let unicodeRaw = withFlatString("(?U)\\p{Lower}+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let unicodeMatch = regexFind(unicodeRaw, input: "AbCäü")
        #expect(unicodeMatch != runtimeNullSentinelInt)
        #expect(matchValue(unicodeMatch) == "b")
    }

    // MARK: - KUU-4169: JVM \p{...} property-name validation

    @Test
    func jvmRegexPropertyErrorRejectsCaseVariantPosixNames() {
        // JVM throws PatternSyntaxException for these; ICU accepts them.
        for pattern in [
            "\\p{lower}", "\\P{lower}", "\\p{LOWER}", "\\p{lOWER}",
            "\\p{upper}", "\\p{ascii}", "\\p{alpha}", "\\p{digit}",
            "\\p{islatin}", "\\p{inGreek}", "\\p{IN_GREEK}",
            "[\\p{lower}]", "x\\p{lower}y", "(a|\\p{lower})",
        ] {
            #expect(jvmRegexPropertyError(pattern) != nil, "expected rejection: \(pattern)")
        }
        // Canonical spellings and the (?U) Unicode-POSIX mode stay valid.
        for pattern in [
            "\\p{Lower}", "\\p{Upper}", "\\p{ASCII}", "\\p{Alpha}",
            "\\p{Lu}", "\\p{L}", "\\pL", "\\p{InGreek}", "\\p{IsLatin}",
            "\\p{Islower}", "\\p{gc=Lu}", "\\p{sc=Latin}", "\\p{blk=Basic Latin}",
            "(?U)\\p{lower}", "(?U)\\p{LOWER}", "(?U)\\p{lOwEr}", "(?U)\\p{xdigit}",
            "(?U:\\p{lower})x(?-U:\\p{Lower})", "\\Q\\p{lower}\\E",
        ] {
            #expect(jvmRegexPropertyError(pattern) == nil, "expected acceptance: \(pattern)")
        }
    }

    @Test
    func jvmRegexPropertyErrorRejectsIcuOnlyPropertyForms() {
        // Property keys java.util.regex does not know (ICU accepts them).
        for pattern in [
            "\\p{scx=Latn}", "\\p{age=3.0}", "\\p{ccc=0}", "\\p{nv=1}",
            "\\p{GCB=XX}", "\\p{lb=XX}", "\\p{WB=XX}", "\\p{ea=F}",
            "\\p{Script_Extensions=Latin}", "\\p{InSC=Latin}",
        ] {
            #expect(jvmRegexPropertyError(pattern) != nil, "expected rejection: \(pattern)")
        }
        // Bare binary property names need the Is prefix on the JVM.
        for pattern in [
            "\\p{Any}", "\\p{any}", "\\p{Word}", "\\p{word}", "\\p{perl}",
            "\\p{join_control}", "\\p{IDS_Binary_Operator}",
            "\\p{Changes_When_Uppercased}", "\\p{graph}", "\\p{gc=lu}",
            "\\p{gc=Decimal_Number}", "\\p{sc=Old Italic}", "\\p{IsBasicLatin}",
            "\\p{blk=No_Block}", "\\p{InNo_Block}",
        ] {
            #expect(jvmRegexPropertyError(pattern) != nil, "expected rejection: \(pattern)")
        }
        for pattern in [
            "\\p{IsAlphabetic}", "\\p{IsEmoji}", "\\p{IsNd}",
            "\\p{gc=Nd}", "\\p{gc=all}", "\\p{gc=ASCII}", "\\p{sc=Ital}",
            "\\p{sc=latn}", "\\p{blk=basic latin}", "\\p{block=Basic Latin}",
            "\\p{Script=GREEK}", "\\p{IsLC}", "\\p{IsL}",
        ] {
            #expect(jvmRegexPropertyError(pattern) == nil, "expected acceptance: \(pattern)")
        }
    }

    @Test
    func jvmRegexPropertyErrorTracksFlagsClassesAndQuotes() {
        // Flag scope: (?U) ends at the enclosing group's ')' on the JVM.
        #expect(jvmRegexPropertyError("(?U)\\p{lower}") == nil)
        #expect(jvmRegexPropertyError("(?U)\\p{lower}(?-U)\\p{lower}") != nil)
        #expect(jvmRegexPropertyError("x(?U)\\p{lower}y(?-U)\\p{lower}") != nil)
        #expect(jvmRegexPropertyError("(a(?U)\\p{lower})\\p{lower}") != nil)
        // 'c' (CANON_EQ) is an inline flag letter too: it must not desync
        // the (?U-...) parse.
        #expect(jvmRegexPropertyError("(?U-c:\\p{lower})") == nil)
        #expect(jvmRegexPropertyError("(?c-U:\\p{lower})") != nil)
        // Inside character classes flag groups are literals, so (?U) there
        // does not enable POSIX names — but \p escapes still validate.
        #expect(jvmRegexPropertyError("(?U)[\\p{lower}]") == nil)
        #expect(jvmRegexPropertyError("[(?U)\\p{lower}]") != nil)
        #expect(jvmRegexPropertyError("[\\p{lower}]") != nil)
        #expect(jvmRegexPropertyError("[\\p{Lu}[x]]") == nil)
        // \Q...\E quotes property-looking text literally, inside and
        // outside classes.
        #expect(jvmRegexPropertyError("\\Q\\p{lower}\\E") == nil)
        #expect(jvmRegexPropertyError("[\\Q\\p{lower}\\E]") == nil)
        #expect(jvmRegexPropertyError("\\\\Q\\p{lower}\\E") != nil)
        // COMMENTS mode: whitespace/comments around the name are skipped,
        // comments work inside classes, and (?-x) turns it back off.
        #expect(jvmRegexPropertyError("(?x)\\p{ Lu}") == nil)
        #expect(jvmRegexPropertyError("(?x)\\p {Lu}") == nil)
        #expect(jvmRegexPropertyError("(?x)\\p {lower}") != nil)
        #expect(jvmRegexPropertyError("(?x)\\p { Lu }") != nil)
        #expect(jvmRegexPropertyError("(?x)[#c\n\\p{ Lu}]") == nil)
        #expect(jvmRegexPropertyError("(?x)(?-x)\\p{ Lu}") != nil)
        #expect(jvmRegexPropertyError("(?x)\\p{Lu }") != nil)
        // Initial COMMENTS state (RegexOption.COMMENTS) applies from the
        // start of the pattern.
        #expect(jvmRegexPropertyError("\\p{ Lu}", commentsInitially: true) == nil)
        #expect(jvmRegexPropertyError("(?-x)\\p{ Lu}", commentsInitially: true) != nil)
        // Malformed property escapes the JVM also rejects.
        for pattern in ["\\p", "\\p{", "\\p}", "\\p{}", "\\p{=}", "\\p{a=b=c}", "\\p{gc=}", "\\p{L }"] {
            #expect(jvmRegexPropertyError(pattern) != nil, "expected rejection: \(pattern)")
        }
    }

    @Test
    func invalidPropertyNamesThrowIllegalArgumentException() {
        for pattern in ["\\p{lower}", "\\p{LOWER}", "\\p{gc=lu}", "\\p{scx=Latn}", "\\p{Any}", "\\p{word}"] {
            var thrown = 0
            let raw = withFlatString(pattern) { data, length, byteCount, hash in
                kk_regex_create_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown != 0, "expected IllegalArgumentException: \(pattern)")
            #expect(raw == 0)
        }
        for pattern in ["\\p{Lower}", "\\p{Lu}", "(?U)\\p{lower}", "(?U)\\p{xdigit}", "\\Q\\p{lower}\\E", "[\\p{IsLatin}]"] {
            var thrown = 0
            let raw = withFlatString(pattern) { data, length, byteCount, hash in
                kk_regex_create_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown == 0, "expected successful compile: \(pattern)")
            #expect(raw != 0)
        }
    }

    @Test
    func commentsOptionEnablesWhitespaceInsidePropertyNames() {
        // RegexOption.COMMENTS (ordinal 4) maps to .allowCommentsAndWhitespace;
        // the JVM's Pattern.COMMENTS flag likewise permits \p{ Lu }.
        var thrown = 0
        let optionRaw = kk_box_int(4)
        let raw = withFlatString("\\p{ Lu}") { data, length, byteCount, hash in
            kk_regex_create_with_option_flat(data, length, byteCount, hash, optionRaw, &thrown)
        }
        #expect(thrown == 0)
        #expect(raw != 0)

        var thrownDefault = 0
        let rejected = withFlatString("\\p{ Lu}") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, &thrownDefault)
        }
        #expect(thrownDefault != 0)
        #expect(rejected == 0)
    }

    @Test
    func validPropertyNamesStillMatch() {
        // Acceptance must not change match semantics: canonical POSIX names
        // keep their KUU-4148 ASCII defaults, and Unicode names match as
        // before.
        let lowerRaw = withFlatString("\\p{Lower}+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let first = regexFind(lowerRaw, input: "AbCäü")
        #expect(first != runtimeNullSentinelInt)
        #expect(matchValue(first) == "b")

        let luRaw = withFlatString("\\p{Lu}+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let luMatch = regexFind(luRaw, input: "aBcD")
        #expect(luMatch != runtimeNullSentinelInt)
        #expect(matchValue(luMatch) == "B")

        let uLowerRaw = withFlatString("(?U)\\p{lower}+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let uMatch = regexFind(uLowerRaw, input: "aéb")
        #expect(uMatch != runtimeNullSentinelInt)
        #expect(matchValue(uMatch) == "aéb")
    }

    // MARK: - KUU-4295: JVM-accepted \p{...} names ICU rejects

    @Test
    func translateRewritesJvmOnlyPropertyNames() {
        // LD = L ∪ Nd, L1 = U+0000–U+00FF, all = Any (JDK CharPredicates).
        #expect(translateJavaPatternForICU("\\p{LD}") == "[\\p{L}\\p{Nd}]")
        #expect(translateJavaPatternForICU("\\P{LD}") == "[^\\p{L}\\p{Nd}]")
        #expect(translateJavaPatternForICU("\\p{L1}") == "[\\x00-\\xFF]")
        #expect(translateJavaPatternForICU("\\P{L1}") == "[^\\x00-\\xFF]")
        #expect(translateJavaPatternForICU("\\p{all}") == "\\p{Any}")
        #expect(translateJavaPatternForICU("\\P{all}") == "\\P{Any}")
        // java* predicates ICU lacks or resolves differently.
        #expect(translateJavaPatternForICU("\\p{javaAlphabetic}") == "\\p{Alphabetic}")
        #expect(translateJavaPatternForICU("\\p{javaIdeographic}") == "\\p{Ideographic}")
        #expect(translateJavaPatternForICU("\\p{javaLowerCase}") == "\\p{Lowercase}")
        #expect(translateJavaPatternForICU("\\p{javaUpperCase}") == "\\p{Uppercase}")
        #expect(translateJavaPatternForICU("\\P{javaLowerCase}") == "\\P{Lowercase}")
        // java* names ICU already resolves identically stay verbatim.
        #expect(translateJavaPatternForICU("\\p{javaDigit}") == "\\p{javaDigit}")
        #expect(translateJavaPatternForICU("\\p{javaWhitespace}") == "\\p{javaWhitespace}")
        // Is* names follow the JVM's forUnicodeProperty → forProperty →
        // forUnicodeScript dispatch, then get the same rewrite as the bare
        // form (ICU rejects every Is<java*> spelling outright).
        #expect(translateJavaPatternForICU("\\p{Isall}") == "\\p{Any}")
        #expect(translateJavaPatternForICU("\\p{IsLD}") == "[\\p{L}\\p{Nd}]")
        #expect(translateJavaPatternForICU("\\p{IsL1}") == "[\\x00-\\xFF]")
        #expect(translateJavaPatternForICU("\\p{IsjavaAlphabetic}") == "\\p{Alphabetic}")
        #expect(translateJavaPatternForICU("\\p{IsjavaIdeographic}") == "\\p{Ideographic}")
        #expect(translateJavaPatternForICU("\\p{IsjavaLowerCase}") == "\\p{Lowercase}")
        #expect(translateJavaPatternForICU("\\p{IsjavaUpperCase}") == "\\p{Uppercase}")
        #expect(translateJavaPatternForICU("\\p{IsjavaDigit}") == "\\p{javaDigit}")
        #expect(translateJavaPatternForICU("\\p{IsjavaWhitespace}") == "\\p{javaWhitespace}")
        #expect(translateJavaPatternForICU("\\p{IsLu}") == "\\p{Lu}")
        #expect(translateJavaPatternForICU("\\P{IsLu}") == "\\P{Lu}")
        #expect(translateJavaPatternForICU("\\p{IsWORD}")
            == "[\\p{Alphabetic}\\p{M}\\p{Nd}\\p{Pc}\\p{Join_Control}]")
        #expect(translateJavaPatternForICU("\\p{Isword}")
            == "[\\p{Alphabetic}\\p{M}\\p{Nd}\\p{Pc}\\p{Join_Control}]")
        #expect(translateJavaPatternForICU("\\p{IsHEXDIGIT}")
            == "[\\p{Nd}A-Fa-f\\uFF21-\\uFF26\\uFF41-\\uFF46]")
        #expect(translateJavaPatternForICU("\\p{IsHEX_DIGIT}")
            == "[\\p{Nd}A-Fa-f\\uFF21-\\uFF26\\uFF41-\\uFF46]")
        #expect(translateJavaPatternForICU("\\p{IsXDIGIT}")
            == "[\\p{Nd}A-Fa-f\\uFF21-\\uFF26\\uFF41-\\uFF46]")
        // Is* names ICU already resolves keep passing through.
        #expect(translateJavaPatternForICU("\\p{IsLatin}") == "\\p{IsLatin}")
        #expect(translateJavaPatternForICU("\\p{Islower}") == "\\p{Islower}")
        #expect(translateJavaPatternForICU("\\p{IsALPHABETIC}") == "\\p{IsALPHABETIC}")
        // gc=/general_category= resolve through forProperty: POSIX values take
        // the ASCII expansion in every mode (?U does not reach forProperty),
        // categories and java* get the same rewrites as bare names.
        #expect(translateJavaPatternForICU("\\p{gc=Lu}") == "\\p{Lu}")
        #expect(translateJavaPatternForICU("\\p{gc=Lower}") == "[a-z]")
        #expect(translateJavaPatternForICU("\\p{general_category=Lower}") == "[a-z]")
        #expect(translateJavaPatternForICU("\\p{gc=ASCII}") == "[\\x00-\\x7F]")
        #expect(translateJavaPatternForICU("\\p{gc=Cntrl}") == "[\\x00-\\x1F\\x7F]")
        #expect(translateJavaPatternForICU("\\p{gc=Digit}") == "[0-9]")
        #expect(translateJavaPatternForICU("\\p{gc=Punct}")
            == "[\\x21-\\x2F\\x3A-\\x40\\x5B-\\x60\\x7B-\\x7E]")
        #expect(translateJavaPatternForICU("\\p{gc=all}") == "\\p{Any}")
        #expect(translateJavaPatternForICU("\\p{gc=LD}") == "[\\p{L}\\p{Nd}]")
        #expect(translateJavaPatternForICU("\\p{gc=L1}") == "[\\x00-\\xFF]")
        #expect(translateJavaPatternForICU("\\p{gc=javaLowerCase}") == "\\p{Lowercase}")
        #expect(translateJavaPatternForICU("\\p{gc=javaDigit}") == "\\p{javaDigit}")
        #expect(translateJavaPatternForICU("\\P{gc=Lower}") == "[^a-z]")
        // The empty Java block SURROGATES_AREA never matches; its complement
        // matches everything.
        #expect(translateJavaPatternForICU("\\p{InSurrogates_Area}") == "\\P{Any}")
        #expect(translateJavaPatternForICU("\\P{InSurrogates_Area}") == "\\p{Any}")
        #expect(translateJavaPatternForICU("\\p{blk=Surrogates_Area}") == "\\P{Any}")
        #expect(translateJavaPatternForICU("\\p{block=surrogates_area}") == "\\P{Any}")
        // Rewrites compose with flags, classes and quotes like the POSIX ones.
        #expect(translateJavaPatternForICU("(?U)\\p{LD}") == "[\\p{L}\\p{Nd}]")
        #expect(translateJavaPatternForICU("(?U)\\p{gc=Lower}") == "[a-z]")
        #expect(translateJavaPatternForICU("(?U)\\p{Lower}") == "\\p{Lower}")
        #expect(translateJavaPatternForICU("[\\p{LD}x]") == "[[\\p{L}\\p{Nd}]x]")
        #expect(translateJavaPatternForICU("[\\p{IsWORD}]")
            == "[[\\p{Alphabetic}\\p{M}\\p{Nd}\\p{Pc}\\p{Join_Control}]]")
        #expect(translateJavaPatternForICU("\\Q\\p{LD}\\E\\p{LD}")
            == "\\Q\\p{LD}\\E[\\p{L}\\p{Nd}]")
    }

    @Test
    func jvmOnlyPropertyNamesCompileAndMatch() {
        func find(_ pattern: String, _ input: String) -> String? {
            var thrown = 0
            let raw = withFlatString(pattern) { data, length, byteCount, hash in
                kk_regex_create_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown == 0, "expected compile: \(pattern)")
            guard raw != 0 else { return nil }
            let match = regexFind(raw, input: input)
            return match == runtimeNullSentinelInt ? nil : matchValue(match)
        }
        // Names ICU rejected before KUU-4295 now compile and match like the
        // JVM: LD = letters ∪ decimal digits, L1 = U+0000–U+00FF.
        #expect(find("\\p{LD}", "a") == "a")
        #expect(find("\\p{LD}", "٥") == "٥")
        #expect(find("\\p{LD}", "_") == nil)
        #expect(find("\\p{L1}", "é") == "é")
        #expect(find("\\p{L1}", "Ā") == nil)
        #expect(find("\\p{all}", " ") == " ")
        // java* predicates.
        #expect(find("\\p{javaAlphabetic}", "a") == "a")
        #expect(find("\\p{javaAlphabetic}", "5") == nil)
        #expect(find("\\p{javaIdeographic}", "一") == "一")
        #expect(find("\\p{javaLowerCase}", "AbC") == "b")
        #expect(find("\\p{javaUpperCase}", "aBc") == "B")
        #expect(find("\\p{javaDigit}", "٥") == "٥")
        #expect(find("\\p{javaWhitespace}", "\t") == "\t")
        // Is* forms, including the JDK WORD and HEX_DIGIT unions.
        #expect(find("\\p{Isall}", "a") == "a")
        #expect(find("\\p{IsLD}", "5") == "5")
        #expect(find("\\p{IsL1}", "A") == "A")
        #expect(find("\\p{IsjavaWhitespace}", " ") == " ")
        #expect(find("\\p{IsWORD}", "_") == "_")
        #expect(find("\\p{IsWORD}", " ") == nil)
        #expect(find("\\p{Isword}", "5") == "5")
        #expect(find("\\p{IsHEXDIGIT}", "٠") == "٠")
        #expect(find("\\p{IsXDIGIT}", "g") == nil)
        // gc=/general_category=: POSIX values are ASCII on the JVM even
        // though ICU would read them as Unicode properties.
        #expect(find("\\p{gc=Lu}", "AbC") == "A")
        #expect(find("\\p{gc=Lower}", "AbC") == "b")
        #expect(find("\\p{gc=Lower}", "ä") == nil)
        #expect(find("\\p{general_category=Lower}", "a") == "a")
        #expect(find("\\p{gc=Nd}", "٥") == "٥")
        #expect(find("\\p{gc=javaLowerCase}", "aB") == "a")
        // Is* POSIX names keep the JVM's Unicode-POSIX predicates: IsLower is
        // isLowerCase (Unicode), unlike the ASCII gc=Lower above.
        #expect(find("\\p{IsLower}", "ä") == "ä")
        // The empty SURROGATES_AREA block never matches; its complement does.
        #expect(find("\\p{InSurrogates_Area}", "abc") == nil)
        #expect(find("\\p{blk=Surrogates_Area}", "abc") == nil)
        #expect(find("\\P{InSurrogates_Area}", "abc") == "a")
    }

    @Test
    func jvmOnlyPropertyNamesAllCompile() {
        // Every name form the JVM accepts but ICU rejected must now compile:
        // the catalogued gc=/general_category= values, bare aliases, all 18
        // java* predicates under both bare and Is* spellings, IsWORD and the
        // HEXDIGIT spellings, and the empty SURROGATES_AREA block.
        let patterns = [
            "\\p{gc=all}", "\\p{gc=L1}", "\\p{gc=LD}",
            "\\p{gc=Lower}", "\\p{gc=ASCII}", "\\p{gc=Alnum}", "\\p{gc=Alpha}",
            "\\p{gc=Blank}", "\\p{gc=Graph}", "\\p{gc=Print}", "\\p{gc=Space}",
            "\\p{gc=Upper}", "\\p{gc=XDigit}", "\\p{gc=Digit}", "\\p{gc=Punct}",
            "\\p{gc=Cntrl}", "\\p{gc=Lu}", "\\p{gc=Nd}",
            "\\p{general_category=all}", "\\p{general_category=Lower}",
            "\\p{gc=javaAlphabetic}", "\\p{gc=javaDefined}", "\\p{gc=javaDigit}",
            "\\p{gc=javaISOControl}", "\\p{gc=javaIdentifierIgnorable}",
            "\\p{gc=javaIdeographic}", "\\p{gc=javaJavaIdentifierPart}",
            "\\p{gc=javaJavaIdentifierStart}", "\\p{gc=javaLetter}",
            "\\p{gc=javaLetterOrDigit}", "\\p{gc=javaLowerCase}",
            "\\p{gc=javaMirrored}", "\\p{gc=javaSpaceChar}", "\\p{gc=javaTitleCase}",
            "\\p{gc=javaUnicodeIdentifierPart}", "\\p{gc=javaUnicodeIdentifierStart}",
            "\\p{gc=javaUpperCase}", "\\p{gc=javaWhitespace}",
            "\\p{LD}", "\\p{L1}", "\\p{all}",
            "\\p{javaAlphabetic}", "\\p{javaIdeographic}", "\\p{javaLowerCase}",
            "\\p{javaUpperCase}", "\\p{javaDigit}", "\\p{javaWhitespace}",
            "\\p{Isall}", "\\p{IsLD}", "\\p{IsL1}",
            "\\p{IsjavaAlphabetic}", "\\p{IsjavaDefined}", "\\p{IsjavaDigit}",
            "\\p{IsjavaISOControl}", "\\p{IsjavaIdentifierIgnorable}",
            "\\p{IsjavaIdeographic}", "\\p{IsjavaJavaIdentifierPart}",
            "\\p{IsjavaJavaIdentifierStart}", "\\p{IsjavaLetter}",
            "\\p{IsjavaLetterOrDigit}", "\\p{IsjavaLowerCase}",
            "\\p{IsjavaMirrored}", "\\p{IsjavaSpaceChar}", "\\p{IsjavaTitleCase}",
            "\\p{IsjavaUnicodeIdentifierPart}", "\\p{IsjavaUnicodeIdentifierStart}",
            "\\p{IsjavaUpperCase}", "\\p{IsjavaWhitespace}",
            "\\p{IsWORD}", "\\p{Isword}", "\\p{IsHEXDIGIT}", "\\p{IsHEX_DIGIT}",
            "\\p{IsXDIGIT}", "\\p{InSurrogates_Area}", "\\p{blk=Surrogates_Area}",
            "\\p{block=Surrogates_Area}",
            "\\P{LD}", "\\P{all}", "\\P{gc=Lower}", "\\P{IsWORD}",
        ]
        for pattern in patterns {
            var thrown = 0
            let raw = withFlatString(pattern) { data, length, byteCount, hash in
                kk_regex_create_flat(data, length, byteCount, hash, &thrown)
            }
            #expect(thrown == 0, "expected compile: \(pattern)")
            #expect(raw != 0, "expected regex object: \(pattern)")
        }
    }

    /// KUU-4319: isolated surrogates are marker-encoded inside Kotlin strings.
    /// ICU must see them as real UTF-16 code units or `\p{Cs}`/`\p{C}` and the
    /// explicit surrogate range can never match, while script/general-category
    /// properties resolve against the wrong character (U+FFFD).
    @Test
    func isolatedSurrogatesMatchJavaUtilRegexProperties() {
        let loneHigh = runtimeKotlinStringFromUTF16CodeUnits([0xD800])
        let loneLow = runtimeKotlinStringFromUTF16CodeUnits([0xDC00])
        let mixed = runtimeKotlinStringFromUTF16CodeUnits([0x61, 0xD800, 0x62])

        func containsMatch(_ pattern: String, _ input: String) -> Bool {
            let regexRaw = withFlatString(pattern) { data, length, byteCount, hash in
                kk_regex_create_flat(data, length, byteCount, hash, nil)
            }
            return withFlatString(input) { data, length, byteCount, hash in
                kk_unbox_bool(kk_regex_containsMatchIn_flat(regexRaw, data, length, byteCount, hash)) == 1
            }
        }

        // java.util.regex matches isolated surrogates for these.
        for pattern in ["\\p{Cs}", "\\p{C}", "[\\uD800-\\uDFFF]", "\\p{IsUNKNOWN}"] {
            #expect(containsMatch(pattern, loneHigh), "\(pattern) vs U+D800")
            #expect(containsMatch(pattern, loneLow), "\(pattern) vs U+DC00")
        }
        // Block properties split the surrogate halves.
        #expect(containsMatch("\\p{InHigh Surrogates}", loneHigh))
        #expect(!containsMatch("\\p{InHigh Surrogates}", loneLow))
        #expect(containsMatch("\\p{InLow Surrogates}", loneLow))
        #expect(!containsMatch("\\p{InLow Surrogates}", loneHigh))
        // JVM assigns surrogates to script Unknown / not Common, Graph or Specials.
        for pattern in ["\\p{IsCOMMON}", "\\p{sc=Common}", "\\p{script=Common}", "\\p{IsGRAPH}", "\\p{InSPECIALS}"] {
            #expect(!containsMatch(pattern, loneHigh), "\(pattern) vs U+D800")
            #expect(!containsMatch(pattern, loneLow), "\(pattern) vs U+DC00")
        }
        #expect(containsMatch("\\p{Cs}", mixed), "surrogate inside longer input")
        // A well-formed surrogate pair is a single supplementary scalar, not Cs.
        let paired = "\u{1F600}"
        #expect(!containsMatch("\\p{Cs}", paired), "paired surrogate must not match Cs")
        #expect(containsMatch("\\p{Cs}", loneHigh), "sanity")
    }

    /// KUU-4319: match results and replacements must carry the surrogate
    /// back out in the Kotlin marker representation, not U+FFFD.
    @Test
    func isolatedSurrogateMatchValuesRoundTrip() {
        let loneHigh = runtimeKotlinStringFromUTF16CodeUnits([0xD800])
        let loneLow = runtimeKotlinStringFromUTF16CodeUnits([0xDC00])

        let regexRaw = withFlatString("(a)?(\\p{Cs})") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        // "xa<isolated high surrogate>b": the match is "a<surrogate>".
        let input = runtimeKotlinStringFromUTF16CodeUnits([0x78, 0x61, 0xD800, 0x62])
        let matchRaw = regexFind(regexRaw, input: input)
        #expect(matchRaw != 0)
        #expect(runtimeKotlinStringUTF16CodeUnits(matchValue(matchRaw)) == [0x61, 0xD800])
        #expect(runtimeString(__kk_match_result_group_value(matchRaw, 1)) == "a")
        #expect(runtimeKotlinStringUTF16CodeUnits(runtimeString(__kk_match_result_group_value(matchRaw, 2))) == [0xD800])
        #expect(__kk_match_result_group_start(matchRaw, 0) == 1)
        #expect(__kk_match_result_group_end(matchRaw, 0) == 2)

        // findAll over two isolated surrogates of different halves; a 'a'
        // separator keeps them unpaired (adjacent D800+DC00 would form one
        // supplementary scalar, which is not Cs).
        let csRegex = withFlatString("\\p{Cs}") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let allInput = runtimeKotlinStringFromUTF16CodeUnits([0xD800, 0x61, 0xDC00])
        let allRaw = withFlatString(allInput) { data, length, byteCount, hash in
            kk_regex_findAll_flat(csRegex, data, length, byteCount, hash)
        }
        let elements = runtimeListElements(allRaw)
        #expect(elements.count == 2)
        if elements.count == 2 {
            #expect(runtimeKotlinStringUTF16CodeUnits(runtimeString(__kk_match_result_group_value(elements[0], 0))) == [0xD800])
            #expect(runtimeKotlinStringUTF16CodeUnits(runtimeString(__kk_match_result_group_value(elements[1], 0))) == [0xDC00])
        }

        // split on the surrogate keeps the surrounding text intact.
        let splitInput = runtimeKotlinStringFromUTF16CodeUnits([0x61, 0xD800, 0x62])
        let splitRaw = withFlatString(splitInput) { data, length, byteCount, hash in
            kk_string_split_regex_flat(data, length, byteCount, hash, csRegex)
        }
        #expect(runtimeListStrings(splitRaw) == ["a", "b"])

        // replace swaps the surrogate for literal text.
        let replaced = kk_string_replace_regex(
            runtimeMakeStringRaw(loneHigh), regexRaw, runtimeString("X"), nil
        )
        #expect(runtimeString(replaced) == "X")

        // matchEntire and next() keep working on surrogate input.
        let entireMatch = withFlatString(loneLow) { data, length, byteCount, hash in
            kk_regex_matchEntire_flat(csRegex, data, length, byteCount, hash)
        }
        #expect(entireMatch != 0)
        #expect(__kk_match_result_next(entireMatch) == runtimeNullSentinelInt)
    }
}
