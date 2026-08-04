@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-REGEX-002: Regex sema resolution and KIR lowering
//
// This file verifies:
//   1. Overload selection at call sites (disambiguates the three Regex constructor overloads)
//   2. RegexOption enum member dispatch (static field resolution)
//   3. Method dispatch for every Regex member (matches / containsMatchIn / find /
//      findAll / matchEntire / replace)
//   4. Named-capture-group access chains produce no sema errors and lower to KIR
//   5. toRegex() String extension lowers to kk_string_toRegex_flat
//   6. String.split(Regex) and String.contains(Regex) lower to the correct KIR callees
//   7. Regex.replace with lambda lowers to kk_regex_replace_lambda
//   8. Regex.fromLiteral (companion) lowers to kk_regex_from_literal_flat in KIR
//
// Scope: sema resolution + KIR lowering only. No runtime edits.
// Does NOT overlap with STDLIB-REGEX-001 (API inventory) or STDLIB-REGEX-003 (runtime).

@Suite
struct RegexSemaLoweringTests {

    // MARK: - Helpers

    /// Collect every callee name emitted across all KIR functions in a module.
    private func allCalleesInModule(_ module: KIRModule, interner: StringInterner) -> Set<String> {
        var result = Set<String>()
        for function in findAllKIRFunctions(in: module) {
            result.formUnion(extractCallees(from: function.body, interner: interner))
        }
        return result
    }

    // MARK: - 1. Constructor overload selection (no-error sema checks)
    // Note: Regex constructors are resolved via the KIR lowering (not stored as
    // callBinding in the sema bindings table). The KIR-level overload tests in
    // section 5 below verify the correct callee is selected. These sema tests
    // confirm that each overload compiles without errors.

    // MARK: - 2. RegexOption enum member dispatch

    // MARK: - 3. Method dispatch for each Regex member

    // MARK: - 4. Named capture group access chain

    // MARK: - 5. KIR lowering: constructor calls emit correct KIR callees

    // MARK: - 6. KIR lowering: member calls emit correct KIR callees

    // MARK: - 7. KIR lowering: String.toRegex()

    // MARK: - 8. KIR lowering: String.toRegex(option) / String.toRegex(options)

    // MARK: - 9. KIR lowering: String.split(Regex) and String.contains(Regex)

    // MARK: - 9. KIR lowering: Regex.fromLiteral (companion)

    // MARK: - 10. KIR lowering: named group access chain produces kk_match_group_collection_get

    // MARK: - 11. KIR lowering: MatchResult component calls

    // MARK: - 12. No stray sema errors on valid Regex programs

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

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testSingleArgConstructorCompilesSemaClean
            """
            package sample0

                    fun test() {
                        val r = Regex("[a-z]+")
                        println(r.containsMatchIn("hello"))
                    }

            """,
            // testTwoArgOptionConstructorCompilesSemaClean
            """
            package sample1

                    fun test() {
                        val r = Regex("foo", RegexOption.IGNORE_CASE)
                        println(r.matches("FOO"))
                    }

            """,
            // testTwoArgSetOptionsConstructorCompilesSemaClean
            """
            package sample2

                    fun test() {
                        val r = Regex("bar", setOf(RegexOption.MULTILINE, RegexOption.DOT_MATCHES_ALL))
                        println(r.containsMatchIn("bar"))
                    }

            """,
            // testRegexOptionIgnoreCaseResolvesSema
            """
            package sample3

                    fun test() {
                        val opt = RegexOption.IGNORE_CASE
                    }

            """,
            // testMatchesBindingResolvesToKkRegexMatches
            """
            package sample4

                    fun test() {
                        val r = Regex("^[0-9]+$")
                        println(r.matches("42"))
                    }

            """,
            // testFindAllBindingResolvesToKkRegexFindAll
            """
            package sample5

                    fun test() {
                        val r = Regex("\\\\d+")
                        val all = r.findAll("abc 1 def 2 ghi 3")
                    }

            """,
            // testReplaceWithLambdaBindingResolvesToKkRegexReplaceLambda
            """
            package sample6

                    fun test() {
                        val r = Regex("\\\\d+")
                        val result = r.replace("abc 1 def 2") { m -> "[${m.value}]" }
                    }

            """,
            // testNamedGroupAccessChainProducesNoSemaErrors
            """
            package sample7

                    fun test() {
                        val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})")
                        val m = r.find("2025-04-17")
                        val year = m?.groups?.get("year")?.value
                        println(year)
                    }

            """,
            // testGroupsByIndexAccessProducesNoSemaErrors
            """
            package sample8

                    fun test() {
                        val r = Regex("(\\\\d+)-(\\\\w+)")
                        val m = r.find("123-abc")
                        val first = m?.groups?.get(1)?.value
                        println(first)
                    }

            """,
            // testGroupValuesListAccessProducesNoSemaErrors
            """
            package sample9

                    fun test() {
                        val r = Regex("(\\\\d+)")
                        val m = r.find("42")
                        val vals = m?.groupValues
                        println(vals)
                    }

            """,
            // testComplexRegexProgramProducesNoSemaErrors
            """
            package sample10

                    fun parseDate(input: String): String? {
                        val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})")
                        val m = r.find(input) ?: return null
                        val year = m.groups.get("year")?.value ?: "?"
                        val month = m.groups.get("month")?.value ?: "?"
                        val day = m.groups.get("day")?.value ?: "?"
                        return "$year/$month/$day"
                    }
                    fun main() {
                        println(parseDate("2025-04-17"))
                    }

            """,
            // testRegexWithAllOptionCombinationsProducesNoSemaErrors
            """
            package sample11

                    fun test() {
                        val r1 = Regex("hello", RegexOption.IGNORE_CASE)
                        val r2 = Regex("world", RegexOption.MULTILINE)
                        val r3 = Regex("foo", RegexOption.DOT_MATCHES_ALL)
                        val r4 = Regex("bar", RegexOption.LITERAL)
                        val r5 = Regex("baz", RegexOption.UNIX_LINES)
                        val r6 = Regex("qux", RegexOption.COMMENTS)
                        val r7 = Regex("quux", RegexOption.CANON_EQ)
                        val rAll = Regex(
                            ".*",
                            setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE,
                                  RegexOption.DOT_MATCHES_ALL, RegexOption.LITERAL)
                        )
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testSingleArgConstructorCompilesSemaClean ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(!sample0Diagnostics.contains { $0.severity == .error },
                               "Single-arg Regex constructor must compile without sema errors")

            }

            // === testTwoArgOptionConstructorCompilesSemaClean ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(!sample1Diagnostics.contains { $0.severity == .error },
                               "Two-arg Regex(String, RegexOption) constructor must compile without sema errors")

            }

            // === testTwoArgSetOptionsConstructorCompilesSemaClean ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(!sample2Diagnostics.contains { $0.severity == .error },
                               "Two-arg Regex(String, Set<RegexOption>) constructor must compile without sema errors")

            }

            // === testRegexOptionIgnoreCaseResolvesSema ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(
                    !sample3Diagnostics.contains { $0.severity == .error },
                    "RegexOption.IGNORE_CASE must resolve without sema errors"
                )

            }

            // === testMatchesBindingResolvesToKkRegexMatches ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let callExpr = try #require(
                    firstExprIDInPath(in: ast, path: sample4Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == "matches"
                    },
                    "Expected .matches(...) member call"
                )
                let binding = try #require(sema.bindings.callBinding(for: callExpr))
                #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_matches_flat")

            }

            // === testFindAllBindingResolvesToKkRegexFindAll ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let callExpr = try #require(
                    firstExprIDInPath(in: ast, path: sample5Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == "findAll"
                    },
                    "Expected .findAll(...) member call"
                )
                let binding = try #require(sema.bindings.callBinding(for: callExpr))
                #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_findAll_flat")

            }

            // === testReplaceWithLambdaBindingResolvesToKkRegexReplaceLambda ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let source = sources[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let callExpr = try #require(
                    firstExprIDInPath(in: ast, path: sample6Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                        guard interner.resolve(callee) == "replace" else { return false }
                        // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                        // String.replace(String, String) internally, and bundled
                        // stdlib is scanned before user source; exclude it so this
                        // finds the user's Regex.replace(...) call.
                        return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                    },
                    "Expected .replace(...) member call"
                )
                let binding = try #require(sema.bindings.callBinding(for: callExpr))
                #expect(
                    sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_regex_replace_lambda"
                )

            }

            // === testNamedGroupAccessChainProducesNoSemaErrors ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                #expect(
                    !sample7Diagnostics.contains { $0.severity == .error },
                    "Named group access chain should have no sema errors"
                )

            }

            // === testGroupsByIndexAccessProducesNoSemaErrors ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                #expect(
                    !sample8Diagnostics.contains { $0.severity == .error },
                    "Group-by-index access chain should have no sema errors"
                )

            }

            // === testGroupValuesListAccessProducesNoSemaErrors ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                #expect(
                    !sample9Diagnostics.contains { $0.severity == .error },
                    "groupValues access should have no sema errors"
                )

            }

            // === testComplexRegexProgramProducesNoSemaErrors ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                #expect(
                    !sample10Diagnostics.contains { $0.severity == .error },
                    "Complex Regex program must produce no sema errors"
                )

            }

            // === testRegexWithAllOptionCombinationsProducesNoSemaErrors ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                #expect(
                    !sample11Diagnostics.contains { $0.severity == .error },
                    "All RegexOption combinations should compile without sema errors"
                )

            }

        }
    }

    // MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRClean() throws {

        let sources: [String] = [
            // testSingleArgRegexConstructorLowersToKkRegexCreate
            """
            package sample0

                    fun test() {
                        val r = Regex("[a-z]+")
                        println(r.matches("hello"))
                    }

            """,
            // testTwoArgOptionRegexConstructorLowersToKkRegexCreateWithOption
            """
            package sample1

                    fun test() {
                        val r = Regex("foo", RegexOption.IGNORE_CASE)
                        println(r.matches("FOO"))
                    }

            """,
            // testSetOptionsRegexConstructorLowersToKkRegexCreateWithOptions
            """
            package sample2

                    fun test() {
                        val r = Regex("bar", setOf(RegexOption.MULTILINE, RegexOption.IGNORE_CASE))
                        println(r.containsMatchIn("bar"))
                    }

            """,
            // testRegexMatchesLowersToKkRegexMatches
            """
            package sample3

                    fun test() {
                        val r = Regex("^\\\\d+$")
                        println(r.matches("123"))
                    }

            """,
            // testRegexContainsMatchInLowersToKkRegexContainsMatchIn
            """
            package sample4

                    fun test() {
                        val r = Regex("[a-z]+")
                        println(r.containsMatchIn("hello world"))
                    }

            """,
            // testRegexFindLowersToKkRegexFind
            """
            package sample5

                    fun test() {
                        val r = Regex("\\\\d+")
                        val m = r.find("abc123")
                        println(m?.value)
                    }

            """,
            // testRegexFindAllLowersToKkRegexFindAll
            """
            package sample6

                    fun test() {
                        val r = Regex("\\\\d+")
                        val ms = r.findAll("a1b2c3")
                    }

            """,
            // testRegexMatchEntireLowersToKkRegexMatchEntire
            """
            package sample7

                    fun test() {
                        val r = Regex("[a-z]+")
                        val m = r.matchEntire("hello")
                        println(m?.value)
                    }

            """,
            // testRegexReplaceWithLambdaLowersToKkRegexReplaceLambda
            """
            package sample8

                    fun test() {
                        val r = Regex("\\\\d+")
                        val result = r.replace("abc 1 def 2") { m -> "[${m.value}]" }
                        println(result)
                    }

            """,
            // testStringToRegexLowersToKkStringToRegex
            """
            package sample9

                    fun test() {
                        val r = "[a-z]+".toRegex()
                        println(r.matches("abc"))
                    }

            """,
            // testStringToRegexWithOptionLowersToKkStringToRegexWithOption
            """
            package sample10

                    fun test() {
                        val r = "[a-z]+".toRegex(RegexOption.IGNORE_CASE)
                        println(r.matches("ABC"))
                    }

            """,
            // testStringToRegexWithOptionsSetLowersToKkStringToRegexWithOptions
            """
            package sample11

                    fun test() {
                        val r = "[a-z]+".toRegex(setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE))
                        println(r.matches("ABC"))
                    }

            """,
            // testStringSplitWithRegexUsesSourceBackedWrapper
            """
            package sample12

                    fun test() {
                        val r = Regex("\\\\s+")
                        val parts = "hello world  foo".split(r)
                        println(parts)
                    }

            """,
            // testStringContainsWithRegexLowersToKkStringContainsRegex
            """
            package sample13

                    fun test() {
                        val r = Regex("\\\\d+")
                        println("abc123".contains(r))
                    }

            """,
            // testRegexFromLiteralLowersToKkRegexFromLiteral
            """
            package sample14

                    fun test() {
                        val r = Regex.fromLiteral("hello.world")
                        println(r.matches("hello.world"))
                    }

            """,
            // testNamedGroupAccessChainLowersToKkMatchGroupCollectionGet
            """
            package sample15

                    fun test() {
                        val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
                        val m = r.find("2025-04")
                        val year = m?.groups?.get("year")?.value
                        println(year)
                    }

            """,
            // testGroupsByIndexLowersToKkMatchGroupCollectionGetAt
            """
            package sample16

                    fun test() {
                        val r = Regex("(\\\\d+)-(\\\\w+)")
                        val m = r.find("123-abc")
                        val first = m?.groups?.get(1)?.value
                        println(first)
                    }

            """,
            // testMatchResultComponent1LowersCorrectly
            """
            package sample17

                    fun test() {
                        val r = Regex("(\\\\w+)")
                        val m = r.find("hello")
                        val v1 = m?.component1()
                        val v2 = m?.component2()
                        println(v1)
                        println(v2)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)

            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            let callees = allCalleesInModule(module, interner: ctx.interner)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testSingleArgRegexConstructorLowersToKkRegexCreate ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(
                    callees.contains("kk_regex_create_flat"),
                    Comment(rawValue: "KIR must contain kk_regex_create for single-arg constructor; found: \(callees)")
                )

            }

            // === testTwoArgOptionRegexConstructorLowersToKkRegexCreateWithOption ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    callees.contains("kk_regex_create_with_option_flat"),
                    Comment(rawValue: "KIR must contain kk_regex_create_with_option; found: \(callees)")
                )

            }

            // === testSetOptionsRegexConstructorLowersToKkRegexCreateWithOptions ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(
                    callees.contains("kk_regex_create_with_options_flat"),
                    Comment(rawValue: "KIR must contain kk_regex_create_with_options; found: \(callees)")
                )

            }

            // === testRegexMatchesLowersToKkRegexMatches ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(callees.contains("kk_regex_matches_flat"), Comment(rawValue: "KIR must contain kk_regex_matches; found: \(callees)"))

            }

            // === testRegexContainsMatchInLowersToKkRegexContainsMatchIn ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(callees.contains("kk_regex_containsMatchIn_flat"), Comment(rawValue: "KIR must contain kk_regex_containsMatchIn; found: \(callees)"))

            }

            // === testRegexFindLowersToKkRegexFind ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                #expect(callees.contains("kk_regex_find_flat"), Comment(rawValue: "KIR must contain kk_regex_find; found: \(callees)"))

            }

            // === testRegexFindAllLowersToKkRegexFindAll ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                #expect(callees.contains("kk_regex_findAll_flat"), Comment(rawValue: "KIR must contain kk_regex_findAll; found: \(callees)"))

            }

            // === testRegexMatchEntireLowersToKkRegexMatchEntire ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                #expect(callees.contains("kk_regex_matchEntire_flat"), Comment(rawValue: "KIR must contain kk_regex_matchEntire; found: \(callees)"))

            }

            // === testRegexReplaceWithLambdaLowersToKkRegexReplaceLambda ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                #expect(callees.contains("kk_regex_replace_lambda"), Comment(rawValue: "KIR must contain kk_regex_replace_lambda; found: \(callees)"))

            }

            // === testStringToRegexLowersToKkStringToRegex ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                #expect(callees.contains("kk_string_toRegex_flat"), Comment(rawValue: "KIR must contain kk_string_toRegex; found: \(callees)"))

            }

            // === testStringToRegexWithOptionLowersToKkStringToRegexWithOption ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                #expect(
                    callees.contains("kk_string_toRegex_with_option_flat"),
                    Comment(rawValue: "KIR must contain kk_string_toRegex_with_option; found: \(callees)")
                )

            }

            // === testStringToRegexWithOptionsSetLowersToKkStringToRegexWithOptions ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                #expect(
                    callees.contains("kk_string_toRegex_with_options_flat"),
                    Comment(rawValue: "KIR must contain kk_string_toRegex_with_options; found: \(callees)")
                )

            }

            // === testStringSplitWithRegexUsesSourceBackedWrapper ===

            do {

                let sample12Path = paths[12]

                let path = sample12Path

                let source = sources[12]

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                #expect(callees.contains("split"), Comment(rawValue: "KIR must call the source-backed split wrapper; found: \(callees)"))
                #expect(
                    !callees.contains("kk_string_split_regex_flat"),
                    Comment(rawValue: "User KIR should not directly lower split(Regex) to runtime; found: \(callees)")
                )

            }

            // === testStringContainsWithRegexLowersToKkStringContainsRegex ===

            do {

                let sample13Path = paths[13]

                let path = sample13Path

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                #expect(callees.contains("kk_string_contains_regex_flat"), Comment(rawValue: "KIR must contain kk_string_contains_regex; found: \(callees)"))

            }

            // === testRegexFromLiteralLowersToKkRegexFromLiteral ===

            do {

                let sample14Path = paths[14]

                let path = sample14Path

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                #expect(callees.contains("kk_regex_from_literal_flat"), Comment(rawValue: "KIR must contain kk_regex_from_literal; found: \(callees)"))

            }

            // === testNamedGroupAccessChainLowersToKkMatchGroupCollectionGet ===

            do {

                let sample15Path = paths[15]

                let path = sample15Path

                let sample15Diagnostics = diagnosticsForPath(sample15Path, in: ctx)

                #expect(
                    callees.contains("kk_match_group_collection_get"),
                    Comment(rawValue: "KIR must contain kk_match_group_collection_get for named group access; found: \(callees)")
                )

            }

            // === testGroupsByIndexLowersToKkMatchGroupCollectionGetAt ===

            do {

                let sample16Path = paths[16]

                let path = sample16Path

                let sample16Diagnostics = diagnosticsForPath(sample16Path, in: ctx)

                #expect(
                    callees.contains("kk_match_group_collection_get_at"),
                    Comment(rawValue: "KIR must contain kk_match_group_collection_get_at for index-based group access; found: \(callees)")
                )

            }

            // === testMatchResultComponent1LowersCorrectly ===

            do {

                let sample17Path = paths[17]

                let path = sample17Path

                let sample17Diagnostics = diagnosticsForPath(sample17Path, in: ctx)

                // Call component1() and component2() explicitly rather than via destructuring,
                // since the compiler lowers val (a, b) = m differently.
                    #expect(
                        callees.contains("kk_match_result_component1"),
                        Comment(rawValue: "KIR must contain kk_match_result_component1; found: \(callees)")
                    )
                    #expect(
                        callees.contains("kk_match_result_component2"),
                        Comment(rawValue: "KIR must contain kk_match_result_component2; found: \(callees)")
                    )

            }

        }
    }

}
