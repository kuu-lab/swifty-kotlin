#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-REGEX-001: kotlin.text.Regex API Surface Inventory
//
// This file catalogues *every* Regex-related symbol that the sema layer registers
// as a synthetic stub and verifies that:
//   • the symbol exists in the symbol table after sema
//   • it is wired to the expected ABI / external-link name
//   • class-member lookups use the correct fully-qualified path
//     (kotlin.text.<ClassName>.<member>)
//   • top-level constructor overloads and companion methods are all present
//
// Scope: signature-level / sema-level only — runtime correctness is covered by
//        RuntimeRegexTests and STDLIB-REGEX-003 (commit #1208).

@Suite
struct RegexAPISurfaceInventoryTests {

    // MARK: - Shared sema fixture

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    // MARK: - Lookup helpers

    /// External link for a kotlin.text-level symbol (top-level or class member).
    private func externalLink(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let interned = fqPath.map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: interned) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    /// True when the FQ path resolves to at least one symbol.
    private func isRegistered(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        !sema.symbols.lookupAll(fqName: fqPath.map { interner.intern($0) }).isEmpty
    }

    /// All external links registered under the given FQ path.
    private func allExternalLinks(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        let interned = fqPath.map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: interned)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    // MARK: - 1. Constructors

    @Test func testRegexSingleArgConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        // Regex(pattern: String) -> Regex
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex"],
            sema: sema,
            interner: interner
        )
        #expect(
            links.contains("kk_regex_create_flat"),
            "Regex(pattern) constructor must link to kk_regex_create_flat"
        )
    }

    @Test func testRegexSingleOptionConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        // Regex(pattern: String, option: RegexOption) -> Regex
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex"],
            sema: sema,
            interner: interner
        )
        #expect(
            links.contains("kk_regex_create_with_option_flat"),
            "Regex(pattern, option) constructor must link to kk_regex_create_with_option_flat"
        )
    }

    @Test func testRegexSetOptionsConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        // Regex(pattern: String, options: Set<RegexOption>) -> Regex
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex"],
            sema: sema,
            interner: interner
        )
        #expect(
            links.contains("kk_regex_create_with_options_flat"),
            "Regex(pattern, options) constructor must link to kk_regex_create_with_options_flat"
        )
    }

    @Test func testAllThreeRegexConstructorOverloadsArePresent() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex"],
            sema: sema,
            interner: interner
        )
        let required: Set<String> = [
            "kk_regex_create_flat",
            "kk_regex_create_with_option_flat",
            "kk_regex_create_with_options_flat",
        ]
        #expect(
            required.isSubset(of: links),
            Comment(rawValue: "All three Regex constructor overloads must be registered; found: \(links)")
        )
    }

    // MARK: - 2. RegexOption enum entries

    @Test func testRegexOptionEnumClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
        let sym = sema.symbols.lookup(fqName: fq)
        #expect(sym != nil, "kotlin.text.RegexOption enum class must exist in symbol table")
    }

    @Test func testRegexOptionAllEnumEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let entries = [
            "IGNORE_CASE", "MULTILINE", "DOT_MATCHES_ALL",
            "LITERAL", "UNIX_LINES", "COMMENTS", "CANON_EQ",
        ]
        for entry in entries {
            let fq = ["kotlin", "text", "RegexOption", entry].map { interner.intern($0) }
            #expect(
                sema.symbols.lookup(fqName: fq) != nil,
                Comment(rawValue: "RegexOption.\(entry) must be registered in symbol table")
            )
        }
    }

    // MARK: - 3. Regex member functions

    @Test func testRegexMatchesIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "matches"],
            sema: sema,
            interner: interner
        )
        #expect(link == "kk_regex_matches_flat", "Regex.matches must link to kk_regex_matches")
    }

    @Test func testRegexContainsMatchInIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "containsMatchIn"],
            sema: sema,
            interner: interner
        )
        #expect(link == "kk_regex_containsMatchIn_flat",
                       "Regex.containsMatchIn must link to kk_regex_containsMatchIn")
    }

    @Test func testRegexFindIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "find"],
            sema: sema,
            interner: interner
        )
        #expect(link == "kk_regex_find_flat", "Regex.find must link to kk_regex_find")
    }

    @Test func testRegexFindAllIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "findAll"],
            sema: sema,
            interner: interner
        )
        #expect(link == "kk_regex_findAll_flat", "Regex.findAll must link to kk_regex_findAll")
    }

    @Test func testRegexMatchEntireIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "matchEntire"],
            sema: sema,
            interner: interner
        )
        #expect(link == "kk_regex_matchEntire_flat",
                       "Regex.matchEntire must link to kk_regex_matchEntire")
    }

    @Test func testRegexReplaceWithLambdaIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "replace"],
            sema: sema,
            interner: interner
        )
        #expect(link == "kk_regex_replace_lambda",
                       "Regex.replace(input, transform) must link to kk_regex_replace_lambda")
    }

    // MARK: - 4. Regex properties

    // KSP-486: pattern / options / groupNames are implemented in bundled Kotlin
    // (kotlin.text.Regex), so they must resolve without a synthetic runtime link.

    @Test func testRegexPatternPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "pattern"],
            sema: sema,
            interner: interner
        )
        #expect(
            isRegistered(fqPath: ["kotlin", "text", "pattern"], sema: sema, interner: interner),
            "Regex.pattern must be registered"
        )
        #expect(links.isEmpty, Comment(rawValue: "Regex.pattern must be source-backed; found: \(links)"))
    }

    @Test func testRegexOptionsPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "options"],
            sema: sema,
            interner: interner
        )
        #expect(
            isRegistered(fqPath: ["kotlin", "text", "options"], sema: sema, interner: interner),
            "Regex.options must be registered"
        )
        #expect(links.isEmpty, Comment(rawValue: "Regex.options must be source-backed; found: \(links)"))
    }

    @Test func testRegexGroupNamesPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "groupNames"],
            sema: sema,
            interner: interner
        )
        #expect(
            isRegistered(fqPath: ["kotlin", "text", "groupNames"], sema: sema, interner: interner),
            "Regex.groupNames must be registered"
        )
        #expect(links.isEmpty, Comment(rawValue: "Regex.groupNames must be source-backed; found: \(links)"))
    }

    // MARK: - 5. Companion methods (fromLiteral)

    @Test func testRegexFromLiteralCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "Regex", "Companion", "fromLiteral"]
            .map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!(syms.isEmpty), "Regex.Companion.fromLiteral must be registered")
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(
            links.contains("kk_regex_from_literal_flat"),
            Comment(rawValue: "Regex.fromLiteral must link to kk_regex_from_literal; found: \(links)")
        )
    }

    // MARK: - 6. MatchResult properties and functions

    // KSP-486: the MatchResult / MatchGroup / MatchGroupCollection members below
    // are implemented in bundled Kotlin (kotlin.text.MatchResult); only their
    // registration is asserted here, and they must carry no runtime link.

    @Test func testMatchResultValueIsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchResult", "value"], sema, interner)
    }

    @Test func testMatchResultRangeIsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchResult", "range"], sema, interner)
    }

    @Test func testMatchResultGroupsIsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchResult", "groups"], sema, interner)
    }

    @Test func testMatchResultGroupValuesIsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchResult", "groupValues"], sema, interner)
    }

    @Test func testMatchResultComponent1IsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchResult", "component1"], sema, interner)
    }

    @Test func testMatchResultComponent2IsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchResult", "component2"], sema, interner)
    }

    @Test func testMatchResultNextIsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchResult", "next"], sema, interner)
    }

    // MARK: - 7. MatchGroupCollection

    @Test func testMatchGroupCollectionGetIsSourceBacked() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchGroupCollection", "get"], sema, interner)
    }

    @Test func testMatchGroupCollectionHasBothGetOverloads() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroupCollection", "get"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(
            syms.count >= 2,
            "MatchGroupCollection.get must have at least 2 overloads (by-name and by-index)"
        )
    }

    @Test func testMatchGroupCollectionSizeIsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchGroupCollection", "size"], sema, interner)
    }

    // MARK: - 8. MatchGroup properties

    @Test func testMatchGroupValueIsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchGroup", "value"], sema, interner)
    }

    @Test func testMatchGroupRangeIsRegistered() throws {
        let (sema, interner) = try makeSema()
        try expectSourceBackedMember(["kotlin", "text", "MatchGroup", "range"], sema, interner)
    }

    // MARK: - 9. String extension: replaceFirst / split with Regex

    @Test func testStringReplaceFirstWithRegexIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "replaceFirst"],
            sema: sema,
            interner: interner
        )
        #expect(
            !links.contains("kk_string_replaceFirst_regex"),
            Comment(rawValue: "kotlin.text.replaceFirst(Regex, String) must be source-backed; found: \(links)")
        )
        let bridgeLink = externalLink(
            fqPath: ["kotlin", "text", "__kk_replaceFirst_regex"],
            sema: sema,
            interner: interner
        )
        #expect(
            bridgeLink == "kk_string_replaceFirst_regex",
            Comment(rawValue: "StringSearchReplace bridge must link to kk_string_replaceFirst_regex; found: \(bridgeLink ?? "nil")")
        )
    }

    @Test func testStringSplitWithRegexIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "split"],
            sema: sema,
            interner: interner
        )
        #expect(
            !links.contains("kk_string_split_regex_flat"),
            Comment(rawValue: "kotlin.text.split(Regex) must be source-backed; found: \(links)")
        )
        let bridgeLink = externalLink(
            fqPath: ["kotlin", "text", "__kk_split_regex"],
            sema: sema,
            interner: interner
        )
        #expect(
            bridgeLink == "kk_string_split_regex_flat",
            Comment(rawValue: "StringSearchReplace bridge must link to kk_string_split_regex_flat; found: \(bridgeLink ?? "nil")")
        )
    }

    // MARK: - 10. Call-site resolution: constructors resolve in Kotlin source

    @Test func testRegexSingleArgConstructorResolvesInCallExpr() throws {
        // Verify that Regex(pattern: String) compiles without sema errors.
        // Symbol-level verification is covered by testRegexSingleArgConstructorIsRegistered
        // and testAllThreeRegexConstructorOverloadsArePresent.
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            println(r.containsMatchIn("abc"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Regex(pattern) should compile without sema errors"
            )
        }
    }

    @Test func testRegexSingleOptionConstructorResolvesInCallExpr() throws {
        let source = """
        fun test() {
            val r = Regex("hello", RegexOption.IGNORE_CASE)
            println(r.matches("HELLO"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let regexCallExprs = allExprIDs(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(calleeName) == "Regex"
            }

            // Pick the call with 2 arguments (the one with an option)
            let twoArgCall = regexCallExprs.first { exprID in
                guard case let .call(_, _, args, _) = ast.arena.expr(exprID) else { return false }
                return args.count == 2
            }
            let callExpr = try #require(twoArgCall, "Expected Regex(pattern, option) call")
            let binding = try #require(sema.bindings.callBinding(for: callExpr))
            #expect(
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_create_with_option_flat"
            )
        }
    }

    @Test func testRegexMatchesMemberCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex("^\\\\d+$")
            println(r.matches("123"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "matches"
            }, "Expected .matches(...) member call")

            let binding = try #require(sema.bindings.callBinding(for: callExpr))
            #expect(
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_matches_flat"
            )
        }
    }

    @Test func testRegexContainsMatchInMemberCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            println(r.containsMatchIn("hello world"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "containsMatchIn"
            }, "Expected .containsMatchIn(...) member call")

            let binding = try #require(sema.bindings.callBinding(for: callExpr))
            #expect(
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_containsMatchIn_flat"
            )
        }
    }

    @Test func testRegexFindMemberCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            val m = r.find("abc123")
            println(m?.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "find"
            }, "Expected .find(...) member call")

            let binding = try #require(sema.bindings.callBinding(for: callExpr))
            #expect(
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_find_flat"
            )
        }
    }

    @Test func testRegexMatchEntireMemberCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            val m = r.matchEntire("hello")
            println(m?.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "matchEntire"
            }, "Expected .matchEntire(...) member call")

            let binding = try #require(sema.bindings.callBinding(for: callExpr))
            #expect(
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_matchEntire_flat"
            )
        }
    }

    @Test func testRegexFromLiteralCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex.fromLiteral("hello.world")
            println(r.matches("hello.world"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "fromLiteral"
            }, "Expected .fromLiteral(...) member call")

            let binding = try #require(sema.bindings.callBinding(for: callExpr))
            #expect(
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_from_literal_flat"
            )
        }
    }

    // MARK: - 11. Named group access resolves at call site

    @Test func testNamedGroupAccessChainResolves() throws {
        let source = """
        fun test() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
            val m = r.find("2025-04")
            val year = m?.groups?.get("year")?.value
            println(year)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // No diagnostics expected for valid named-group access chain.
            #expect(
                !(ctx.diagnostics.hasError),
                "Named group access chain should produce no sema errors"
            )
        }
    }

    // MARK: - 12. Option combination (setOf) compiles without sema errors

    @Test func testRegexOptionSetCombinationCompiles() throws {
        let source = """
        fun test() {
            val r = Regex(
                "^hello",
                setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE, RegexOption.DOT_MATCHES_ALL)
            )
            println(r.containsMatchIn("HELLO"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Regex option set combination should compile without sema errors"
            )
        }
    }

    // MARK: - 13. Empty pattern compiles

    @Test func testEmptyPatternCompiles() throws {
        let source = """
        fun test() {
            val r = Regex("")
            println(r.matches(""))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Empty pattern Regex should compile without sema errors"
            )
        }
    }

    // MARK: - 14. Unicode pattern compiles

    @Test func testUnicodePatternCompiles() throws {
        let source = """
        fun test() {
            val r = Regex("[\\u00C0-\\u024F]+")
            println(r.matches("café"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Unicode pattern Regex should compile without sema errors"
            )
        }
    }

    // MARK: - 15. Symbol table completeness: all mandatory API symbols present

    @Test func testMandatoryAPISymbolsAreAllRegistered() throws {
        let (sema, interner) = try makeSema()

        // Each (fqPath, expectedLinkName) pair must be present.
        // nil linkName means we only check symbol existence, not the link.
        let mandatoryLinks: [([String], String)] = [
            // Constructors (top-level in kotlin.text)
            (["kotlin", "text", "Regex"], "kk_regex_create_flat"),
            (["kotlin", "text", "Regex"], "kk_regex_create_with_option_flat"),
            (["kotlin", "text", "Regex"], "kk_regex_create_with_options_flat"),
            // Member functions
            (["kotlin", "text", "Regex", "matches"], "kk_regex_matches_flat"),
            (["kotlin", "text", "Regex", "containsMatchIn"], "kk_regex_containsMatchIn_flat"),
            (["kotlin", "text", "Regex", "find"], "kk_regex_find_flat"),
            (["kotlin", "text", "Regex", "findAll"], "kk_regex_findAll_flat"),
            (["kotlin", "text", "Regex", "matchEntire"], "kk_regex_matchEntire_flat"),
            (["kotlin", "text", "Regex", "replace"], "kk_regex_replace_lambda"),
            // Companion
            (["kotlin", "text", "Regex", "Companion", "fromLiteral"], "kk_regex_from_literal_flat"),
            // String extensions
            (["kotlin", "text", "matches"], "kk_string_matches_regex_flat"),
            (["kotlin", "text", "contains"], "kk_string_contains_regex_flat"),
            (["kotlin", "text", "__kk_replace_regex"], "kk_string_replace_regex"),
            (["kotlin", "text", "__kk_replaceFirst_regex"], "kk_string_replaceFirst_regex"),
            (["kotlin", "text", "__kk_split_regex"], "kk_string_split_regex_flat"),
            (["kotlin", "text", "toRegex"], "kk_string_toRegex_flat"),
            (["kotlin", "text", "toRegex"], "kk_string_toRegex_with_option_flat"),
            (["kotlin", "text", "toRegex"], "kk_string_toRegex_with_options_flat"),
        ]

        for (fqPath, expectedLink) in mandatoryLinks {
            let links = allExternalLinks(fqPath: fqPath, sema: sema, interner: interner)
            #expect(
                links.contains(expectedLink),
                Comment(rawValue: "Missing API: \(fqPath.joined(separator: ".")) -> \(expectedLink) (found: \(links))")
            )
        }

        // KSP-486: source-backed members — registered, but without runtime links.
        let sourceBackedMembers: [[String]] = [
            ["kotlin", "text", "pattern"],
            ["kotlin", "text", "options"],
            ["kotlin", "text", "groupNames"],
            ["kotlin", "text", "MatchResult", "value"],
            ["kotlin", "text", "MatchResult", "range"],
            ["kotlin", "text", "MatchResult", "groups"],
            ["kotlin", "text", "MatchResult", "groupValues"],
            ["kotlin", "text", "MatchResult", "component1"],
            ["kotlin", "text", "MatchResult", "component2"],
            ["kotlin", "text", "MatchResult", "next"],
            ["kotlin", "text", "MatchGroup", "value"],
            ["kotlin", "text", "MatchGroup", "range"],
            ["kotlin", "text", "MatchGroupCollection", "get"],
            ["kotlin", "text", "MatchGroupCollection", "size"],
        ]
        for fqPath in sourceBackedMembers {
            try expectSourceBackedMember(fqPath, sema, interner)
        }
    }

    /// Asserts the FQ path resolves and every registration is source-backed
    /// (i.e. carries no synthetic runtime link name).
    private func expectSourceBackedMember(
        _ fqPath: [String],
        _ sema: SemaModule,
        _ interner: StringInterner
    ) throws {
        let name = fqPath.joined(separator: ".")
        #expect(
            isRegistered(fqPath: fqPath, sema: sema, interner: interner),
            Comment(rawValue: "\(name) must be registered")
        )
        let links = allExternalLinks(fqPath: fqPath, sema: sema, interner: interner)
        #expect(links.isEmpty, Comment(rawValue: "\(name) must be source-backed; found: \(links)"))
    }

    // MARK: - Helpers

    private func allExprIDs(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }
}
#endif
