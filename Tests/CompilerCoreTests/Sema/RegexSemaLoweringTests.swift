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
//   5. toRegex() String extension lowers to __kk_string_toRegex_flat
//   6. String.split(Regex) and String.contains(Regex) lower to the correct KIR callees
//   7. Regex.replace with lambda lowers to __kk_regex_replace_lambda
//   8. Regex.fromLiteral (companion) lowers to __kk_regex_from_literal_flat in KIR
//
// Scope: sema resolution + KIR lowering only. No runtime edits.
// Does NOT overlap with STDLIB-REGEX-001 (API inventory) or STDLIB-REGEX-003 (runtime).

@Suite
struct RegexSemaLoweringTests {

    // MARK: - Helpers

    private static nonisolated(unsafe) var _sharedRegexKIRCtx: CompilationContext?

    private func sharedRegexKIRCtx(at _: Int) throws -> CompilationContext {
        if let cached = Self._sharedRegexKIRCtx {
            return cached
        }

        let sources: [String] = [
            """
            package regexcase0

            fun regexCase0() {
                val r = Regex("[a-z]+")
                println(r.matches("hello"))
            }
            """,
            """
            package regexcase1

            fun regexCase1() {
                val r = Regex("foo", RegexOption.IGNORE_CASE)
                println(r.matches("FOO"))
            }
            """,
            """
            package regexcase2

            fun regexCase2() {
                val r = Regex("bar", setOf(RegexOption.MULTILINE, RegexOption.IGNORE_CASE))
                println(r.containsMatchIn("bar"))
            }
            """,
            """
            package regexcase3

            fun regexCase3() {
                val r = Regex("^\\\\d+$")
                println(r.matches("123"))
            }
            """,
            """
            package regexcase4

            fun regexCase4() {
                val r = Regex("[a-z]+")
                println(r.containsMatchIn("hello world"))
            }
            """,
            """
            package regexcase5

            fun regexCase5() {
                val r = Regex("\\\\d+")
                val m = r.find("abc123")
                println(m?.value)
            }
            """,
            """
            package regexcase6

            fun regexCase6() {
                val r = Regex("\\\\d+")
                val ms = r.findAll("a1b2c3")
            }
            """,
            """
            package regexcase7

            fun regexCase7() {
                val r = Regex("[a-z]+")
                val m = r.matchEntire("hello")
                println(m?.value)
            }
            """,
            """
            package regexcase8

            fun regexCase8() {
                val r = Regex("\\\\d+")
                val result = r.replace("abc 1 def 2") { m -> "[${m.value}]" }
                println(result)
            }
            """,
            """
            package regexcase9

            fun regexCase9() {
                val r = "[a-z]+".toRegex()
                println(r.matches("abc"))
            }
            """,
            """
            package regexcase10

            fun regexCase10() {
                val r = "[a-z]+".toRegex(RegexOption.IGNORE_CASE)
                println(r.matches("ABC"))
            }
            """,
            """
            package regexcase11

            fun regexCase11() {
                val r = "[a-z]+".toRegex(setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE))
                println(r.matches("ABC"))
            }
            """,
            """
            package regexcase12

            fun regexCase12() {
                val r = Regex("\\\\s+")
                val parts = "hello world  foo".split(r)
                println(parts)
            }
            """,
            """
            package regexcase13

            fun regexCase13() {
                val r = Regex("\\\\d+")
                println("abc123".contains(r))
            }
            """,
            """
            package regexcase14

            fun regexCase14() {
                val r = Regex.fromLiteral("hello.world")
                println(r.matches("hello.world"))
            }
            """,
            """
            package regexcase15

            fun regexCase15() {
                val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
                val m = r.find("2025-04")
                val year = m?.groups?.get("year")?.value
                println(year)
            }
            """,
            """
            package regexcase16

            fun regexCase16() {
                val r = Regex("(\\\\d+)-(\\\\w+)")
                val m = r.find("123-abc")
                val first = m?.groups?.get(1)?.value
                println(first)
            }
            """,
            """
            package regexcase17

            fun regexCase17() {
                val r = Regex("(\\\\w+)")
                val m = r.find("hello")
                val v1 = m?.component1()
                val v2 = m?.component2()
                println(v1)
                println(v2)
            }
            """,
        ]

        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        Self._sharedRegexKIRCtx = ctx
        return ctx
    }

    // MARK: - 1. Constructor overload selection (no-error sema checks)
    // Note: Regex constructors are resolved via the KIR lowering (not stored as
    // callBinding in the sema bindings table). The KIR-level overload tests in
    // section 5 below verify the correct callee is selected. These sema tests
    // confirm that each overload compiles without errors.

    @Test func testSingleArgConstructorCompilesSemaClean() throws {
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            println(r.containsMatchIn("hello"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError,
                           "Single-arg Regex constructor must compile without sema errors")
        }
    }

    @Test func testTwoArgOptionConstructorCompilesSemaClean() throws {
        let source = """
        fun test() {
            val r = Regex("foo", RegexOption.IGNORE_CASE)
            println(r.matches("FOO"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError,
                           "Two-arg Regex(String, RegexOption) constructor must compile without sema errors")
        }
    }

    @Test func testTwoArgSetOptionsConstructorCompilesSemaClean() throws {
        let source = """
        fun test() {
            val r = Regex("bar", setOf(RegexOption.MULTILINE, RegexOption.DOT_MATCHES_ALL))
            println(r.containsMatchIn("bar"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError,
                           "Two-arg Regex(String, Set<RegexOption>) constructor must compile without sema errors")
        }
    }

    // MARK: - 2. RegexOption enum member dispatch

    @Test func testRegexOptionIgnoreCaseResolvesSema() throws {
        let source = """
        fun test() {
            val opt = RegexOption.IGNORE_CASE
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "RegexOption.IGNORE_CASE must resolve without sema errors"
            )
        }
    }

    @Test func testAllRegexOptionEntriesResolveWithoutErrors() throws {
        let entries = [
            "IGNORE_CASE", "MULTILINE", "DOT_MATCHES_ALL",
            "LITERAL", "UNIX_LINES", "COMMENTS", "CANON_EQ",
        ]
        for entry in entries {
            let source = """
            fun test() {
                val opt = RegexOption.\(entry)
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)
                #expect(
                    !ctx.diagnostics.hasError,
                    "RegexOption.\(entry) must resolve without sema errors"
                )
            }
        }
    }

    // MARK: - 3. Method dispatch for each Regex member

    @Test func testMatchesBindingResolvesToKkRegexMatches() throws {
        let source = """
        fun test() {
            val r = Regex("^[0-9]+$")
            println(r.matches("42"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "matches"
                },
                "Expected .matches(...) member call"
            )
            let binding = try #require(sema.bindings.callBinding(for: callExpr))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == "__kk_regex_matches_flat")
        }
    }

    @Test func testFindAllBindingResolvesToKkRegexFindAll() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            val all = r.findAll("abc 1 def 2 ghi 3")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "findAll"
                },
                "Expected .findAll(...) member call"
            )
            let binding = try #require(sema.bindings.callBinding(for: callExpr))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == "__kk_regex_findAll_flat")
        }
    }

    @Test func testReplaceWithLambdaBindingResolvesToKkRegexReplaceLambda() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            val result = r.replace("abc 1 def 2") { m -> "[${m.value}]" }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                    guard ctx.interner.resolve(callee) == "replace" else { return false }
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
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "__kk_regex_replace_lambda"
            )
        }
    }

    // MARK: - 4. Named capture group access chain

    @Test func testNamedGroupAccessChainProducesNoSemaErrors() throws {
        let source = """
        fun test() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})")
            val m = r.find("2025-04-17")
            val year = m?.groups?.get("year")?.value
            println(year)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Named group access chain should have no sema errors"
            )
        }
    }

    @Test func testGroupsByIndexAccessProducesNoSemaErrors() throws {
        let source = """
        fun test() {
            val r = Regex("(\\\\d+)-(\\\\w+)")
            val m = r.find("123-abc")
            val first = m?.groups?.get(1)?.value
            println(first)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Group-by-index access chain should have no sema errors"
            )
        }
    }

    @Test func testGroupValuesListAccessProducesNoSemaErrors() throws {
        let source = """
        fun test() {
            val r = Regex("(\\\\d+)")
            val m = r.find("42")
            val vals = m?.groupValues
            println(vals)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "groupValues access should have no sema errors"
            )
        }
    }

    // MARK: - 5. KIR lowering: constructor calls emit correct KIR callees

    @Test func testSingleArgRegexConstructorLowersToKkRegexCreate() throws {
        let ctx = try sharedRegexKIRCtx(at: 0)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase0", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_regex_create_flat"),
                Comment(rawValue: "KIR must contain kk_regex_create for single-arg constructor; found: \(callees)")
            )
    }

    @Test func testTwoArgOptionRegexConstructorLowersToKkRegexCreateWithOption() throws {
        let ctx = try sharedRegexKIRCtx(at: 1)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase1", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_regex_create_with_option_flat"),
                Comment(rawValue: "KIR must contain kk_regex_create_with_option; found: \(callees)")
            )
    }

    @Test func testSetOptionsRegexConstructorLowersToKkRegexCreateWithOptions() throws {
        let ctx = try sharedRegexKIRCtx(at: 2)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase2", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_regex_create_with_options_flat"),
                Comment(rawValue: "KIR must contain kk_regex_create_with_options; found: \(callees)")
            )
    }

    // MARK: - 6. KIR lowering: member calls emit correct KIR callees

    @Test func testRegexMatchesLowersToKkRegexMatches() throws {
        let ctx = try sharedRegexKIRCtx(at: 3)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase3", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_regex_matches_flat"), Comment(rawValue: "KIR must contain kk_regex_matches; found: \(callees)"))
    }

    @Test func testRegexContainsMatchInLowersToKkRegexContainsMatchIn() throws {
        let ctx = try sharedRegexKIRCtx(at: 4)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase4", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_regex_containsMatchIn_flat"), Comment(rawValue: "KIR must contain kk_regex_containsMatchIn; found: \(callees)"))
    }

    @Test func testRegexFindLowersToKkRegexFind() throws {
        let ctx = try sharedRegexKIRCtx(at: 5)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase5", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_regex_find_flat"), Comment(rawValue: "KIR must contain kk_regex_find; found: \(callees)"))
    }

    @Test func testRegexFindAllLowersToKkRegexFindAll() throws {
        let ctx = try sharedRegexKIRCtx(at: 6)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase6", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_regex_findAll_flat"), Comment(rawValue: "KIR must contain kk_regex_findAll; found: \(callees)"))
    }

    @Test func testRegexMatchEntireLowersToKkRegexMatchEntire() throws {
        let ctx = try sharedRegexKIRCtx(at: 7)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase7", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_regex_matchEntire_flat"), Comment(rawValue: "KIR must contain kk_regex_matchEntire; found: \(callees)"))
    }

    @Test func testRegexReplaceWithLambdaLowersToKkRegexReplaceLambda() throws {
        let ctx = try sharedRegexKIRCtx(at: 8)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase8", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_regex_replace_lambda"), Comment(rawValue: "KIR must contain __kk_regex_replace_lambda; found: \(callees)"))
    }

    // MARK: - 7. KIR lowering: String.toRegex()

    @Test func testStringToRegexLowersToKkStringToRegex() throws {
        let ctx = try sharedRegexKIRCtx(at: 9)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase9", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_string_toRegex_flat"), Comment(rawValue: "KIR must contain kk_string_toRegex; found: \(callees)"))
    }

    // MARK: - 8. KIR lowering: String.toRegex(option) / String.toRegex(options)

    @Test func testStringToRegexWithOptionLowersToKkStringToRegexWithOption() throws {
        let ctx = try sharedRegexKIRCtx(at: 10)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase10", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_string_toRegex_with_option_flat"),
                Comment(rawValue: "KIR must contain kk_string_toRegex_with_option; found: \(callees)")
            )
    }

    @Test func testStringToRegexWithOptionsSetLowersToKkStringToRegexWithOptions() throws {
        let ctx = try sharedRegexKIRCtx(at: 11)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase11", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_string_toRegex_with_options_flat"),
                Comment(rawValue: "KIR must contain kk_string_toRegex_with_options; found: \(callees)")
            )
    }

    // MARK: - 9. KIR lowering: String.split(Regex) and String.contains(Regex)

    @Test func testStringSplitWithRegexUsesSourceBackedWrapper() throws {
        let ctx = try sharedRegexKIRCtx(at: 12)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase12", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("split"), Comment(rawValue: "KIR must call the source-backed split wrapper; found: \(callees)"))
            #expect(
                !callees.contains("kk_string_split_regex_flat"),
                Comment(rawValue: "User KIR should not directly lower split(Regex) to runtime; found: \(callees)")
            )
    }

    @Test func testStringContainsWithRegexLowersToKkStringContainsRegex() throws {
        let ctx = try sharedRegexKIRCtx(at: 13)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase13", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_string_contains_regex_flat"), Comment(rawValue: "KIR must contain kk_string_contains_regex; found: \(callees)"))
    }

    // MARK: - 9. KIR lowering: Regex.fromLiteral (companion)

    @Test func testRegexFromLiteralLowersToKkRegexFromLiteral() throws {
        let ctx = try sharedRegexKIRCtx(at: 14)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase14", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("__kk_regex_from_literal_flat"), Comment(rawValue: "KIR must contain kk_regex_from_literal; found: \(callees)"))
    }

    // MARK: - 10. KIR lowering: group access goes through the raw match-data bridges

    @Test func testNamedGroupAccessChainLowersToGroupIndexOfNameBridge() throws {
        let ctx = try sharedRegexKIRCtx(at: 15)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase15", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("get") && callees.contains("groups"),
                Comment(rawValue: "Named group access must dispatch to the Kotlin MatchGroupCollection API; found: \(callees)")
            )
            #expect(
                !callees.contains("kk_match_group_collection_get"),
                Comment(rawValue: "kk_match_group_collection_get must be gone; found: \(callees)")
            )
    }

    @Test func testGroupsByIndexLowersToGroupPositionBridges() throws {
        let ctx = try sharedRegexKIRCtx(at: 16)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "regexCase16", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("get") && callees.contains("groups"),
                Comment(rawValue: "Index-based group access must dispatch to the Kotlin MatchGroupCollection API; found: \(callees)")
            )
            #expect(
                !callees.contains("kk_match_group_collection_get_at"),
                Comment(rawValue: "kk_match_group_collection_get_at must be gone; found: \(callees)")
            )
    }

    // MARK: - 11. KIR lowering: MatchResult component calls

    @Test func testMatchResultComponent1LowersCorrectly() throws {
        // Call component1() and component2() explicitly rather than via destructuring,
        // since the compiler lowers val (a, b) = m differently.
        let ctx = try sharedRegexKIRCtx(at: 17)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "regexCase17", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("component1") && callees.contains("component2"),
            Comment(rawValue: "componentN must dispatch to the Kotlin MatchResult API; found: \(callees)")
        )
        #expect(
            !callees.contains("kk_match_result_component1"),
            Comment(rawValue: "kk_match_result_component1 must be gone; found: \(callees)")
        )
    }

    // MARK: - 12. No stray sema errors on valid Regex programs

    @Test func testComplexRegexProgramProducesNoSemaErrors() throws {
        let source = """
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
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Complex Regex program must produce no sema errors"
            )
        }
    }

    @Test func testRegexWithAllOptionCombinationsProducesNoSemaErrors() throws {
        let source = """
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
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "All RegexOption combinations should compile without sema errors"
            )
        }
    }

}
