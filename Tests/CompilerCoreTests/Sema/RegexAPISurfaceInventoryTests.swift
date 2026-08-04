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

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testRegexSingleArgConstructorIsRegistered
            """
            package sample0
            fun noop() {}
            """,
            // testRegexSingleOptionConstructorIsRegistered
            """
            package sample1
            fun noop() {}
            """,
            // testRegexSetOptionsConstructorIsRegistered
            """
            package sample2
            fun noop() {}
            """,
            // testAllThreeRegexConstructorOverloadsArePresent
            """
            package sample3
            fun noop() {}
            """,
            // testRegexOptionEnumClassIsRegistered
            """
            package sample4
            fun noop() {}
            """,
            // testRegexOptionAllEnumEntriesAreRegistered
            """
            package sample5
            fun noop() {}
            """,
            // testRegexMatchesIsRegistered
            """
            package sample6
            fun noop() {}
            """,
            // testRegexContainsMatchInIsRegistered
            """
            package sample7
            fun noop() {}
            """,
            // testRegexFindIsRegistered
            """
            package sample8
            fun noop() {}
            """,
            // testRegexFindAllIsRegistered
            """
            package sample9
            fun noop() {}
            """,
            // testRegexMatchEntireIsRegistered
            """
            package sample10
            fun noop() {}
            """,
            // testRegexReplaceWithLambdaIsRegistered
            """
            package sample11
            fun noop() {}
            """,
            // testRegexPatternPropertyIsRegistered
            """
            package sample12
            fun noop() {}
            """,
            // testRegexOptionsPropertyIsRegistered
            """
            package sample13
            fun noop() {}
            """,
            // testRegexGroupNamesPropertyIsRegistered
            """
            package sample14
            fun noop() {}
            """,
            // testRegexFromLiteralCompanionMethodIsRegistered
            """
            package sample15
            fun noop() {}
            """,
            // testMatchResultValueIsRegistered
            """
            package sample16
            fun noop() {}
            """,
            // testMatchResultRangeIsRegistered
            """
            package sample17
            fun noop() {}
            """,
            // testMatchResultGroupsIsRegistered
            """
            package sample18
            fun noop() {}
            """,
            // testMatchResultGroupValuesIsRegistered
            """
            package sample19
            fun noop() {}
            """,
            // testMatchResultComponent1IsRegistered
            """
            package sample20
            fun noop() {}
            """,
            // testMatchResultComponent2IsRegistered
            """
            package sample21
            fun noop() {}
            """,
            // testMatchResultNextIsRegistered
            """
            package sample22
            fun noop() {}
            """,
            // testMatchGroupCollectionGetByNameIsRegistered
            """
            package sample23
            fun noop() {}
            """,
            // testMatchGroupCollectionGetByIndexIsRegistered
            """
            package sample24
            fun noop() {}
            """,
            // testMatchGroupCollectionHasBothGetOverloads
            """
            package sample25
            fun noop() {}
            """,
            // testMatchGroupCollectionSizeIsRegistered
            """
            package sample26
            fun noop() {}
            """,
            // testMatchGroupValueIsRegistered
            """
            package sample27
            fun noop() {}
            """,
            // testMatchGroupRangeIsRegistered
            """
            package sample28
            fun noop() {}
            """,
            // testStringReplaceFirstWithRegexIsRegistered
            """
            package sample29
            fun noop() {}
            """,
            // testStringSplitWithRegexIsRegistered
            """
            package sample30
            fun noop() {}
            """,
            // testRegexSingleArgConstructorResolvesInCallExpr
            """
            package sample31

                    fun test() {
                        val r = Regex("[a-z]+")
                        println(r.containsMatchIn("abc"))
                    }

            """,
            // testRegexSingleOptionConstructorResolvesInCallExpr
            """
            package sample32

                    fun test() {
                        val r = Regex("hello", RegexOption.IGNORE_CASE)
                        println(r.matches("HELLO"))
                    }

            """,
            // testRegexMatchesMemberCallResolvesCorrectly
            """
            package sample33

                    fun test() {
                        val r = Regex("^\\\\d+$")
                        println(r.matches("123"))
                    }

            """,
            // testRegexContainsMatchInMemberCallResolvesCorrectly
            """
            package sample34

                    fun test() {
                        val r = Regex("[a-z]+")
                        println(r.containsMatchIn("hello world"))
                    }

            """,
            // testRegexFindMemberCallResolvesCorrectly
            """
            package sample35

                    fun test() {
                        val r = Regex("\\\\d+")
                        val m = r.find("abc123")
                        println(m?.value)
                    }

            """,
            // testRegexMatchEntireMemberCallResolvesCorrectly
            """
            package sample36

                    fun test() {
                        val r = Regex("[a-z]+")
                        val m = r.matchEntire("hello")
                        println(m?.value)
                    }

            """,
            // testRegexFromLiteralCallResolvesCorrectly
            """
            package sample37

                    fun test() {
                        val r = Regex.fromLiteral("hello.world")
                        println(r.matches("hello.world"))
                    }

            """,
            // testNamedGroupAccessChainResolves
            """
            package sample38

                    fun test() {
                        val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
                        val m = r.find("2025-04")
                        val year = m?.groups?.get("year")?.value
                        println(year)
                    }

            """,
            // testRegexOptionSetCombinationCompiles
            """
            package sample39

                    fun test() {
                        val r = Regex(
                            "^hello",
                            setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE, RegexOption.DOT_MATCHES_ALL)
                        )
                        println(r.containsMatchIn("HELLO"))
                    }

            """,
            // testEmptyPatternCompiles
            """
            package sample40

                    fun test() {
                        val r = Regex("")
                        println(r.matches(""))
                    }

            """,
            // testUnicodePatternCompiles
            """
            package sample41

                    fun test() {
                        val r = Regex("[\\u00C0-\\u024F]+")
                        println(r.matches("café"))
                    }

            """,
            // testMandatoryAPISymbolsAreAllRegistered
            """
            package sample42
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testRegexSingleArgConstructorIsRegistered ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

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

            // === testRegexSingleOptionConstructorIsRegistered ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

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

            // === testRegexSetOptionsConstructorIsRegistered ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

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

            // === testAllThreeRegexConstructorOverloadsArePresent ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

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

            // === testRegexOptionEnumClassIsRegistered ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let fq = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
                let sym = sema.symbols.lookup(fqName: fq)
                #expect(sym != nil, "kotlin.text.RegexOption enum class must exist in symbol table")

            }

            // === testRegexOptionAllEnumEntriesAreRegistered ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

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

            // === testRegexMatchesIsRegistered ===

            do {

                let sample6Path = paths[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "Regex", "matches"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_regex_matches_flat", "Regex.matches must link to kk_regex_matches")

            }

            // === testRegexContainsMatchInIsRegistered ===

            do {

                let sample7Path = paths[7]

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "Regex", "containsMatchIn"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_regex_containsMatchIn_flat",
                               "Regex.containsMatchIn must link to kk_regex_containsMatchIn")

            }

            // === testRegexFindIsRegistered ===

            do {

                let sample8Path = paths[8]

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "Regex", "find"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_regex_find_flat", "Regex.find must link to kk_regex_find")

            }

            // === testRegexFindAllIsRegistered ===

            do {

                let sample9Path = paths[9]

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "Regex", "findAll"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_regex_findAll_flat", "Regex.findAll must link to kk_regex_findAll")

            }

            // === testRegexMatchEntireIsRegistered ===

            do {

                let sample10Path = paths[10]

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "Regex", "matchEntire"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_regex_matchEntire_flat",
                               "Regex.matchEntire must link to kk_regex_matchEntire")

            }

            // === testRegexReplaceWithLambdaIsRegistered ===

            do {

                let sample11Path = paths[11]

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "Regex", "replace"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_regex_replace_lambda",
                               "Regex.replace(input, transform) must link to kk_regex_replace_lambda")

            }

            // === testRegexPatternPropertyIsRegistered ===

            do {

                let sample12Path = paths[12]

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "Regex", "pattern"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_regex_pattern", "Regex.pattern must link to kk_regex_pattern")

            }

            // === testRegexOptionsPropertyIsRegistered ===

            do {

                let sample13Path = paths[13]

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "Regex", "options"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_regex_options", "Regex.options must link to kk_regex_options")

            }

            // === testRegexGroupNamesPropertyIsRegistered ===

            do {

                let sample14Path = paths[14]

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "Regex", "groupNames"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_regex_group_names",
                               "Regex.groupNames must link to kk_regex_group_names")

            }

            // === testRegexFromLiteralCompanionMethodIsRegistered ===

            do {

                let sample15Path = paths[15]

                let sample15Diagnostics = diagnosticsForPath(sample15Path, in: ctx)

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

            // === testMatchResultValueIsRegistered ===

            do {

                let sample16Path = paths[16]

                let sample16Diagnostics = diagnosticsForPath(sample16Path, in: ctx)

                // MatchResult.value has multiple registrations (on MatchResult and MatchGroup);
                // verify the MatchResult one exists.
                let fq = ["kotlin", "text", "MatchResult", "value"].map { interner.intern($0) }
                let syms = sema.symbols.lookupAll(fqName: fq)
                let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(
                    links.contains("kk_match_result_value"),
                    Comment(rawValue: "MatchResult.value must link to kk_match_result_value; found: \(links)")
                )

            }

            // === testMatchResultRangeIsRegistered ===

            do {

                let sample17Path = paths[17]

                let sample17Diagnostics = diagnosticsForPath(sample17Path, in: ctx)

                let fq = ["kotlin", "text", "MatchResult", "range"].map { interner.intern($0) }
                let syms = sema.symbols.lookupAll(fqName: fq)
                let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(
                    links.contains("kk_match_result_range"),
                    Comment(rawValue: "MatchResult.range must link to kk_match_result_range; found: \(links)")
                )

            }

            // === testMatchResultGroupsIsRegistered ===

            do {

                let sample18Path = paths[18]

                let sample18Diagnostics = diagnosticsForPath(sample18Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "MatchResult", "groups"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_match_result_groups",
                               "MatchResult.groups must link to kk_match_result_groups")

            }

            // === testMatchResultGroupValuesIsRegistered ===

            do {

                let sample19Path = paths[19]

                let sample19Diagnostics = diagnosticsForPath(sample19Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "MatchResult", "groupValues"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_match_result_groupValues",
                               "MatchResult.groupValues must link to kk_match_result_groupValues")

            }

            // === testMatchResultComponent1IsRegistered ===

            do {

                let sample20Path = paths[20]

                let sample20Diagnostics = diagnosticsForPath(sample20Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "MatchResult", "component1"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_match_result_component1",
                               "MatchResult.component1() must link to kk_match_result_component1")

            }

            // === testMatchResultComponent2IsRegistered ===

            do {

                let sample21Path = paths[21]

                let sample21Diagnostics = diagnosticsForPath(sample21Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "MatchResult", "component2"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_match_result_component2",
                               "MatchResult.component2() must link to kk_match_result_component2")

            }

            // === testMatchResultNextIsRegistered ===

            do {

                let sample22Path = paths[22]

                let sample22Diagnostics = diagnosticsForPath(sample22Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "MatchResult", "next"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_match_result_next",
                               "MatchResult.next() must link to kk_match_result_next")

            }

            // === testMatchGroupCollectionGetByNameIsRegistered ===

            do {

                let sample23Path = paths[23]

                let sample23Diagnostics = diagnosticsForPath(sample23Path, in: ctx)

                let fq = ["kotlin", "text", "MatchGroupCollection", "get"].map { interner.intern($0) }
                let syms = sema.symbols.lookupAll(fqName: fq)
                let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(
                    links.contains("kk_match_group_collection_get"),
                    Comment(rawValue: "MatchGroupCollection.get(name) must link to kk_match_group_collection_get; found: \(links)")
                )

            }

            // === testMatchGroupCollectionGetByIndexIsRegistered ===

            do {

                let sample24Path = paths[24]

                let sample24Diagnostics = diagnosticsForPath(sample24Path, in: ctx)

                let fq = ["kotlin", "text", "MatchGroupCollection", "get"].map { interner.intern($0) }
                let syms = sema.symbols.lookupAll(fqName: fq)
                let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(
                    links.contains("kk_match_group_collection_get_at"),
                    Comment(rawValue: "MatchGroupCollection.get(index) must link to kk_match_group_collection_get_at; found: \(links)")
                )

            }

            // === testMatchGroupCollectionHasBothGetOverloads ===

            do {

                let sample25Path = paths[25]

                let sample25Diagnostics = diagnosticsForPath(sample25Path, in: ctx)

                let fq = ["kotlin", "text", "MatchGroupCollection", "get"].map { interner.intern($0) }
                let syms = sema.symbols.lookupAll(fqName: fq)
                #expect(
                    syms.count >= 2,
                    "MatchGroupCollection.get must have at least 2 overloads (by-name and by-index)"
                )

            }

            // === testMatchGroupCollectionSizeIsRegistered ===

            do {

                let sample26Path = paths[26]

                let sample26Diagnostics = diagnosticsForPath(sample26Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "MatchGroupCollection", "size"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_match_group_collection_size",
                               "MatchGroupCollection.size must link to kk_match_group_collection_size")

            }

            // === testMatchGroupValueIsRegistered ===

            do {

                let sample27Path = paths[27]

                let sample27Diagnostics = diagnosticsForPath(sample27Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "MatchGroup", "value"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_match_group_value",
                               "MatchGroup.value must link to kk_match_group_value")

            }

            // === testMatchGroupRangeIsRegistered ===

            do {

                let sample28Path = paths[28]

                let sample28Diagnostics = diagnosticsForPath(sample28Path, in: ctx)

                let link = externalLink(
                    fqPath: ["kotlin", "text", "MatchGroup", "range"],
                    sema: sema,
                    interner: interner
                )
                #expect(link == "kk_match_group_range",
                               "MatchGroup.range must link to kk_match_group_range")

            }

            // === testStringReplaceFirstWithRegexIsRegistered ===

            do {

                let sample29Path = paths[29]

                let sample29Diagnostics = diagnosticsForPath(sample29Path, in: ctx)

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

            // === testStringSplitWithRegexIsRegistered ===

            do {

                let sample30Path = paths[30]

                let sample30Diagnostics = diagnosticsForPath(sample30Path, in: ctx)

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

            // === testRegexSingleArgConstructorResolvesInCallExpr ===

            do {

                let sample31Path = paths[31]

                let sample31Diagnostics = diagnosticsForPath(sample31Path, in: ctx)

                #expect(
                    !(sample31Diagnostics.contains { $0.severity == .error }),
                    "Regex(pattern) should compile without sema errors"
                )

            }

            // === testRegexSingleOptionConstructorResolvesInCallExpr ===

            do {

                let sample32Path = paths[32]

                let sample32Diagnostics = diagnosticsForPath(sample32Path, in: ctx)

                let regexCallExprs = allExprIDsInPath(in: ast, path: sample32Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(calleeName) == "Regex"
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

            // === testRegexMatchesMemberCallResolvesCorrectly ===

            do {

                let sample33Path = paths[33]

                let sample33Diagnostics = diagnosticsForPath(sample33Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample33Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "matches"
                }, "Expected .matches(...) member call")

                let binding = try #require(sema.bindings.callBinding(for: callExpr))
                #expect(
                    sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_matches_flat"
                )

            }

            // === testRegexContainsMatchInMemberCallResolvesCorrectly ===

            do {

                let sample34Path = paths[34]

                let sample34Diagnostics = diagnosticsForPath(sample34Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample34Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "containsMatchIn"
                }, "Expected .containsMatchIn(...) member call")

                let binding = try #require(sema.bindings.callBinding(for: callExpr))
                #expect(
                    sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_containsMatchIn_flat"
                )

            }

            // === testRegexFindMemberCallResolvesCorrectly ===

            do {

                let sample35Path = paths[35]

                let sample35Diagnostics = diagnosticsForPath(sample35Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample35Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "find"
                }, "Expected .find(...) member call")

                let binding = try #require(sema.bindings.callBinding(for: callExpr))
                #expect(
                    sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_find_flat"
                )

            }

            // === testRegexMatchEntireMemberCallResolvesCorrectly ===

            do {

                let sample36Path = paths[36]

                let sample36Diagnostics = diagnosticsForPath(sample36Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample36Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "matchEntire"
                }, "Expected .matchEntire(...) member call")

                let binding = try #require(sema.bindings.callBinding(for: callExpr))
                #expect(
                    sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_matchEntire_flat"
                )

            }

            // === testRegexFromLiteralCallResolvesCorrectly ===

            do {

                let sample37Path = paths[37]

                let sample37Diagnostics = diagnosticsForPath(sample37Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample37Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "fromLiteral"
                }, "Expected .fromLiteral(...) member call")

                let binding = try #require(sema.bindings.callBinding(for: callExpr))
                #expect(
                    sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_from_literal_flat"
                )

            }

            // === testNamedGroupAccessChainResolves ===

            do {

                let sample38Path = paths[38]

                let sample38Diagnostics = diagnosticsForPath(sample38Path, in: ctx)

                // No diagnostics expected for valid named-group access chain.
                #expect(
                    !(sample38Diagnostics.contains { $0.severity == .error }),
                    "Named group access chain should produce no sema errors"
                )

            }

            // === testRegexOptionSetCombinationCompiles ===

            do {

                let sample39Path = paths[39]

                let sample39Diagnostics = diagnosticsForPath(sample39Path, in: ctx)

                #expect(
                    !(sample39Diagnostics.contains { $0.severity == .error }),
                    "Regex option set combination should compile without sema errors"
                )

            }

            // === testEmptyPatternCompiles ===

            do {

                let sample40Path = paths[40]

                let sample40Diagnostics = diagnosticsForPath(sample40Path, in: ctx)

                #expect(
                    !(sample40Diagnostics.contains { $0.severity == .error }),
                    "Empty pattern Regex should compile without sema errors"
                )

            }

            // === testUnicodePatternCompiles ===

            do {

                let sample41Path = paths[41]

                let sample41Diagnostics = diagnosticsForPath(sample41Path, in: ctx)

                #expect(
                    !(sample41Diagnostics.contains { $0.severity == .error }),
                    "Unicode pattern Regex should compile without sema errors"
                )

            }

            // === testMandatoryAPISymbolsAreAllRegistered ===

            do {

                let sample42Path = paths[42]

                let sample42Diagnostics = diagnosticsForPath(sample42Path, in: ctx)

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
                    // Properties
                    (["kotlin", "text", "Regex", "pattern"], "kk_regex_pattern"),
                    (["kotlin", "text", "Regex", "options"], "kk_regex_options"),
                    (["kotlin", "text", "Regex", "groupNames"], "kk_regex_group_names"),
                    // Companion
                    (["kotlin", "text", "Regex", "Companion", "fromLiteral"], "kk_regex_from_literal_flat"),
                    // MatchResult
                    (["kotlin", "text", "MatchResult", "value"], "kk_match_result_value"),
                    (["kotlin", "text", "MatchResult", "range"], "kk_match_result_range"),
                    (["kotlin", "text", "MatchResult", "groups"], "kk_match_result_groups"),
                    (["kotlin", "text", "MatchResult", "groupValues"], "kk_match_result_groupValues"),
                    (["kotlin", "text", "MatchResult", "component1"], "kk_match_result_component1"),
                    (["kotlin", "text", "MatchResult", "component2"], "kk_match_result_component2"),
                    (["kotlin", "text", "MatchResult", "next"], "kk_match_result_next"),
                    // MatchGroup
                    (["kotlin", "text", "MatchGroup", "value"], "kk_match_group_value"),
                    (["kotlin", "text", "MatchGroup", "range"], "kk_match_group_range"),
                    // MatchGroupCollection
                    (["kotlin", "text", "MatchGroupCollection", "get"], "kk_match_group_collection_get"),
                    (["kotlin", "text", "MatchGroupCollection", "get"], "kk_match_group_collection_get_at"),
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

            }

        }
    }

}

#endif
