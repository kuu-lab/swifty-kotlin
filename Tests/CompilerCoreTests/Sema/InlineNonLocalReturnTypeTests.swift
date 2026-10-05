@testable import CompilerCore
import Testing

/// Covers the type of an unlabeled return that exits a lambda passed to an
/// inline higher-order function. The lambda's Boolean predicate type must not
/// be used as the expected type for the returned value.
@Suite
struct InlineNonLocalReturnTypeTests {
    @Test func functionNameLabelsUseTheEnclosingReturnType() throws {
        let ctx = makeContextFromSource("""
        inline fun invokeBlock(block: () -> Unit) { block() }
        inline fun String.tryIt(block: () -> Unit) { block() }
        inline fun predicate(block: () -> Boolean): Boolean { return block() }
        fun h() { invokeBlock { return@h } }
        fun f(s: String) { s.tryIt { return@f } }
        fun typed(): String {
            predicate { return@typed "outer" }
            return "fallback"
        }
        fun nested(): Int {
            invokeBlock { invokeBlock { return@nested 7 } }
            return -1
        }
        fun direct(): Int { return@direct 3 }
        fun withLocal(): String {
            fun local(): Int {
                invokeBlock { return@local 9 }
                return 0
            }
            local()
            return "ok"
        }
        fun withLocalExtension(): Int {
            fun Int.local(): Int {
                invokeBlock { return@local this + 1 }
                return -1
            }
            return 2.local()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        #expect(ctx.sema?.bindings.functionReturnLambdaPaths.count == 7)
    }

    @Test func lambdaLabelsShadowFunctionNameLabels() throws {
        let ctx = makeContextFromSource("""
        inline fun predicate(block: () -> Boolean): Boolean { return block() }
        inline fun same(block: () -> Boolean): Boolean { return block() }
        fun explicit(): String {
            predicate explicit@ { return@explicit true }
            return "ok"
        }
        fun same(): String {
            same { return@same true }
            return "ok"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        #expect(ctx.sema?.bindings.functionReturnLambdaPaths.isEmpty == true)
    }

    @Test(arguments: ["value", "out", "get"])
    func softKeywordFunctionNameLabelsUseTheEnclosingReturnType(name: String) throws {
        let ctx = makeContextFromSource("""
        inline fun invokeBlock(block: () -> Unit) { block() }
        fun \(name)(): Int {
            invokeBlock { return@\(name) 9 }
            return -1
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        #expect(ctx.sema?.bindings.functionReturnLambdaPaths.count == 1)
    }

    @Test func wrongFunctionNameLabeledReturnTypeIsRejected() throws {
        let ctx = makeContextFromSource("""
        inline fun predicate(block: () -> Boolean): Boolean { return block() }
        fun wrong(): String {
            predicate { return@wrong true }
            return "fallback"
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test(arguments: [
        "plain { return@outer }",
        "cross { return@outer }",
        "no { return@outer }",
        "val block = { return@outer }",
        "inlineBlock { plain { return@outer } }",
        "plain { inlineBlock { return@outer } }",
        "cross { inlineBlock { return@outer } }",
        "fun local() { inlineBlock { return@outer } }; local()",
        "inlineBlock(fun() { return@outer })",
        "inlineBlock { return@missing }",
    ])
    func illegalFunctionNameReturnIsRejected(statement: String) throws {
        let ctx = makeContextFromSource("""
        fun plain(block: () -> Unit) { block() }
        inline fun inlineBlock(block: () -> Unit) { block() }
        inline fun cross(crossinline block: () -> Unit) { block() }
        inline fun no(noinline block: () -> Unit) { block() }
        fun outer() { \(statement) }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }

    @Test func nonLocalReturnsUseTheEnclosingFunctionType() throws {
        let ctx = makeContextFromSource("""
        fun firstNonLocal(source: CharSequence): Char {
            return source.first { return '!' }
        }

        fun firstConditionalNonLocal(source: CharSequence): Char {
            return source.first { ch ->
                if (ch == 'x') return '!'
                false
            }
        }

        fun trimNonLocal(source: String): String {
            source.trim { return "!" }
            return "?"
        }

        fun trimStartNonLocal(source: String): String {
            source.trimStart { return "!" }
            return "?"
        }

        fun labeledPredicateReturn(source: CharSequence): Char {
            return source.first { return@first true }
        }

        fun explicitLambdaLabelReturn(source: CharSequence): Char {
            return source.first predicate@ { return@predicate true }
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected non-local return values to use the enclosing function type, got: "
                + errors.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            )
        )
    }

    @Test func wrongEnclosingReturnTypeIsRejected() throws {
        let ctx = makeContextFromSource("""
        fun wrongOuterReturnType(source: CharSequence): Char {
            source.first { return "!" }
            return '?'
        }
        """)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func wrongLabeledPredicateReturnTypeIsRejected() throws {
        let ctx = makeContextFromSource("""
        fun wrongLabeledReturnType(source: CharSequence): Char {
            return source.first { return@first '!' }
        }
        """)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func localNamedFunctionResetsTheEnclosingReturnType() throws {
        let ctx = makeContextFromSource("""
        fun localNamedFunctionReturn(source: CharSequence): String {
            fun local(): Char {
                return source.first { return '!' }
            }
            local()
            return "?"
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
    }
}

private func assertHasDiagnostic(_ code: String, in ctx: CompilationContext) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    let descriptions = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
    #expect(found, "Expected diagnostic \(code), got: \(descriptions)")
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
