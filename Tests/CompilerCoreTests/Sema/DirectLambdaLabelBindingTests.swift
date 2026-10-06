@testable import CompilerCore
import Testing

/// KUU-1402: `name@` is a unary prefix on the whole postfix-unary expression,
/// not just the lambda literal. When a postfix suffix follows the lambda —
/// a direct call `()`, member call, indexing, `!!`, and friends — the label
/// denotes the invoke expression rather than the lambda, so `return@label`
/// inside must be rejected (kotlinc: "target label does not denote a
/// function"). Parenthesized forms like `(foo@{ return@foo 7 })()` keep the
/// label on the lambda because the postfix suffix binds outside the parens.
@Suite
struct DirectLambdaLabelBindingTests {
    @Test func directCallLabelIsNotAReturnTarget() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(foo@{ return@foo 7 }())
        }
        """)

        try runSema(ctx)
        assertLabelDoesNotDenoteFunction("foo", in: ctx)
    }

    @Test func memberCallSuffixLabelIsNotAReturnTarget() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(foo@{ return@foo 7 }.invoke())
        }
        """)

        try runSema(ctx)
        assertLabelDoesNotDenoteFunction("foo", in: ctx)
    }

    @Test func notNullSuffixLabelIsNotAReturnTarget() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(foo@{ return@foo 7 }!!)
        }
        """)

        try runSema(ctx)
        assertLabelDoesNotDenoteFunction("foo", in: ctx)
    }

    @Test func indexSuffixLabelIsNotAReturnTarget() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(foo@{ return@foo 7 }[0])
        }
        """)

        try runSema(ctx)
        assertLabelDoesNotDenoteFunction("foo", in: ctx)
    }

    @Test func parenthesizedLabeledLambdaKeepsFunctionLabel() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println((foo@{ return@foo 7 })())
        }
        """)

        try runSema(ctx)
        assertNoErrors(in: ctx)
    }

    @Test func labeledLambdaArgumentKeepsFunctionLabel() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(run(foo@{ return@foo 7 }))
        }
        """)

        try runSema(ctx)
        assertNoErrors(in: ctx)
    }

    /// KUU-1429: `as`/`as?` are infix casts, not postfix suffixes, so a label
    /// on the operand lambda still denotes the lambda itself — `return@foo`
    /// inside must resolve (and the whole call must type-check).
    @Test func asCastLabeledLambdaKeepsFunctionLabel() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(foo@{ return@foo 7 } as () -> Int)
        }
        """)

        try runSema(ctx)
        assertNoErrors(in: ctx)
    }

    @Test func asQuestionCastLabeledLambdaKeepsFunctionLabel() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(foo@{ return@foo 7 } as? () -> Int)
        }
        """)

        try runSema(ctx)
        assertNoErrors(in: ctx)
    }

    @Test func storedLabeledLambdaKeepsFunctionLabel() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val f = foo@{ return@foo 7 }
            println(f())
        }
        """)

        try runSema(ctx)
        assertNoErrors(in: ctx)
    }

    @Test func innerNonFunctionLabelShadowsOuterLambdaLabel() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            run(foo@{
                println(foo@{ return@foo 7 }())
            })
        }
        """)

        try runSema(ctx)
        assertLabelDoesNotDenoteFunction("foo", in: ctx)
    }

    @Test func loopLabelStillRejectedAsLambdaReturnTarget() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            foo@ while (true) {
                run { return@foo }
            }
        }
        """)

        try runSema(ctx)
        let diags = ctx.diagnostics.diagnostics
        let matched = diags.contains {
            $0.code == "KSWIFTK-SEMA-0042" && $0.severity == .error
                && $0.message.contains("does not reference a valid enclosing lambda")
        }
        #expect(matched, "Expected SEMA-0042 invalid-enclosing-lambda diagnostic, got: \(diags.map { "\($0.code): \($0.message)" })")
    }
}

private func assertLabelDoesNotDenoteFunction(_ label: String, in ctx: CompilationContext) {
    let diags = ctx.diagnostics.diagnostics
    let matched = diags.contains {
        $0.code == "KSWIFTK-SEMA-0042" && $0.severity == .error
            && $0.message.contains("Target label '\(label)' does not denote a function")
    }
    #expect(matched, "Expected SEMA-0042 label-not-a-function diagnostic, got: \(diags.map { "\($0.code): \($0.message)" })")
}

private func assertNoErrors(in ctx: CompilationContext) {
    let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
    #expect(errors.isEmpty, "Expected no errors, got: \(errors.map { "\($0.code): \($0.message)" })")
}
