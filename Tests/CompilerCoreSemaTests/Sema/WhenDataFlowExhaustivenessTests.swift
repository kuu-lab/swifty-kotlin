#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// `when` exhaustiveness over locals whose value is statically known.
/// kotlinc narrows non-null enum/sealed subjects through data flow but
/// keeps requiring the full case set for Boolean and nullable subjects.
@Suite
struct WhenDataFlowExhaustivenessTests {
    @Test func testEnumEntryConstantLocalIsExhaustive() throws {
        let source = """
        enum class E { A, B }
        fun test() {
            val e = E.A
            when (e) { E.A -> println(1) }
            val x = when (e) { E.A -> 1 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testVarWithUnmodifiedConstantIsExhaustive() throws {
        let source = """
        enum class E { A, B }
        fun test() {
            var v = E.A
            val x = when (v) { E.A -> 1 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testBooleanConstantLocalStillRequiresFullCaseSet() throws {
        let source = """
        fun test() {
            val b = true
            val x = when (b) { true -> 1 }
            var c = false
            c = true
            val y = when (c) { true -> 1 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0004"
        }.count == 2, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testNullableSubjectStillRequiresFullCaseSet() throws {
        let source = """
        enum class E { A, B }
        fun test() {
            val e: E? = E.A
            val x = when (e) { E.A -> 1 }
            val n: E? = null
            val y = when (n) { null -> 1 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0004"
        }.count == 2, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testUnknownSubjectsStillRejected() throws {
        let sources = [
            "enum class E { A, B }\nfun test(e: E) = when (e) { E.A -> 1 }",
            "enum class E { A, B }\nfun test() { val e: E = E.A; val x = when (e) { E.A -> 1 } }",
            "enum class E { A, B }\nfun test() { var v: E = E.A; val x = when (v) { E.A -> 1 } }",
            """
            enum class E { A, B }
            fun read(): E = E.B
            fun test() { var u = E.A; u = read(); val x = when (u) { E.A -> 1 } }
            """,
            """
            enum class E { A, B }
            fun test() { var v = E.A; v = E.B; val x = when (v) { E.A -> 1 } }
            """,
            """
            enum class E { A, B }
            fun test(c: Boolean) { var w = E.A; if (c) w = E.B; val x = when (w) { E.A -> 1 } }
            """,
        ]
        let packagedSources = sources.enumerated().map { "package value\($0.offset)\n\($0.element)" }
        try withTemporaryFiles(contents: packagedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-0004" }.count == 1)
            }
        }
    }

    @Test func testReassignmentAndBranchJoinKeepNarrowing() throws {
        let source = """
        enum class E { A, B }
        fun test(c: Boolean) {
            var v = E.A
            v = E.A
            val a = when (v) { E.A -> 1 }
            var m = E.A
            if (c) { m = E.A } else { m = E.B }
            val b = when (m) { E.A -> 1; E.B -> 2 }
            var x = E.A
            if (c) { x = E.A }
            val d = when (x) { E.A -> 1 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testStandaloneAssignmentNarrowsSingletons() throws {
        let source = """
        enum class E { A, B }
        sealed class S { object O1 : S(); object O2 : S() }
        fun read(): E? = E.B
        fun readE(): E = E.B
        fun readS(): S = S.O2
        fun test() {
            val e: E
            e = E.A
            val a = when (e) { E.A -> 1 }
            var n: E? = read()
            n = E.A
            val b = when (n) { E.A -> 1 }
            var z: E? = E.A
            z = null
            val c = when (z) { null -> 1 }
            var s: S = readS()
            s = S.O1
            val d = when (s) { S.O1 -> 1 }
            var v = E.A
            v = readE()
            v = E.B
            val f = when (v) { E.B -> 1 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testNullableEqualityNarrowingIsExhaustive() throws {
        let source = """
        enum class E { A, B }
        fun test(e: E?): Int {
            if (e == E.A) return 0
            return when (e) { E.B -> 1; null -> 2 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testEqualityNarrowedEnumSubjectIsExhaustive() throws {
        let source = """
        enum class E { A, B }
        fun test(e: E) {
            if (e == E.A) {
                val x = when (e) { E.A -> 1 }
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    // KUU-4024: `is T` + `null` covers the whole `T?` domain, so a `when`
    // over a nullable subject is exhaustive without `else`; a covering
    // check alone suffices on a non-null subject, and `is T?` covers
    // `T?` (null included) by itself — matching kotlinc.
    @Test func testNullableSubjectExhaustedByIsCheckAndNullBranch() throws {
        let source = """
        enum class E { A, B }
        sealed class S { object O1 : S(); object O2 : S() }
        fun takesInt(x: Int) = x
        fun test(n: Int?, s: String?, e: E?, b: Boolean?, ss: S?, a: Any?) {
            val r1 = when (n) { is Int -> 1; null -> 0 }
            val r2 = when (s) { is String -> 1; null -> 0 }
            val r3 = when (e) { is E -> 1; null -> 0 }
            val r4 = when (b) { is Boolean -> 1; null -> 0 }
            val r5 = when (ss) { is S -> 1; null -> 0 }
            val r6 = when (a) { is Any -> 1; null -> 0 }
            val r7 = when (n) { is Number -> 1; null -> 0 }
            val r8 = when (n) { is Int? -> 1 }
            val r9 = when (n) { null -> 0; is Int -> takesInt(n) }
        }
        fun <T> generic(x: T?) = when (x) { is Any -> 1; null -> 0 }
        fun <T : Any> nonNullBound(x: T) = when (x) { is Any -> 1 }
        fun <T : Int?> intBound(x: T) = when (x) { is Int -> 1; null -> 0 }
        fun testNonNull(i: Int, anyV: Any) {
            val r1 = when (i) { is Int -> 1 }
            val r2 = when (anyV) { is Any -> 1 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    // KUU-4024: the same coverage must not over-accept — `is T` without a
    // `null` branch leaves `T?`'s null uncovered, `is X` for a disjoint X
    // covers nothing, and a guarded `is` branch cannot be counted.
    @Test func testNullableSubjectStillRejectsIncompleteIsCoverage() throws {
        let source = """
        enum class E { A, B }
        fun test(n: Int?, a: Any?, e: E?, c: Boolean) {
            val r1 = when (n) { is Int -> 1 }
            val r2 = when (a) { is Int -> 1; null -> 0 }
            val r3 = when (n) { is String? -> 1 }
            val r4 = when (n) { is Int if c -> 1; null -> 0 }
            val r5 = when (e) { E.A -> 1; null -> 0 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0004"
        }.count == 5, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
