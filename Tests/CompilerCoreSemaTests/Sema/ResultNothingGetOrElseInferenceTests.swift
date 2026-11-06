#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-564: `Result<Nothing>` must let `getOrElse` infer its fallback type.
@Suite
struct ResultNothingGetOrElseInferenceTests {
    @Test func testNothingResultGetOrElseInfersFallbackType() throws {
        let source = """
        fun inferred(): Int {
            val direct = runCatching { error("boom") }.getOrElse { -2 }
            val chained = runCatching { error("boom") }.onFailure { println(it.message) }.getOrElse { -4 }
            return direct + chained
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let getOrElseCalls = memberCallExprIDs(
                named: "getOrElse",
                in: ast,
                path: path,
                ctx: ctx,
                interner: ctx.interner
            )
            #expect(getOrElseCalls.count >= 2)
            #expect(getOrElseCalls.allSatisfy { sema.bindings.exprType(for: $0) == sema.types.intType })
        }
    }

    @Test func testGetOrElseStillRejectsFallbackOutsideExpectedType() throws {
        let source = """
        fun incompatible(): Int {
            val result: Result<Int> = runCatching { 1 }
            return result.getOrElse { "wrong" }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertHasDiagnostic("KSWIFTK-SEMA-0469", in: ctx)
        }
    }

    /// KUU-4180: `getOrElse` is `<R, T : R>` — the fallback may return any
    /// supertype of the element, so `Result<T>.toState()` must accept a
    /// fallback that is not a `T`. The bundled member signature pins the
    /// lambda to `T`, so the member-call special inference owns the real
    /// semantics; the implicit-receiver form must reach it too.
    @Test func testImplicitReceiverGetOrElseAllowsSupertypeFallback() throws {
        let source = """
        class CompletedExceptionally(val cause: Throwable)

        fun <T> Result<T>.toState(): Any? = getOrElse { CompletedExceptionally(it) }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// KUU-4180: `getOrDefault(defaultValue: R)` is `<R, T : R>` too — an
    /// unqualified call on an implicit `Result<T>` receiver must infer the
    /// join of the element and default types rather than pinning to `T`.
    @Test func testImplicitReceiverGetOrDefaultAllowsSupertypeDefault() throws {
        let source = """
        fun <T> Result<T>.describe(): Any? = getOrDefault("empty")
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// KUU-4180: same `<R, T : R>` shape through an explicit `this`
    /// receiver, which takes the member-call path directly.
    @Test func testExplicitReceiverGetOrElseAllowsSupertypeFallback() throws {
        let source = """
        class CompletedExceptionally(val cause: Throwable)

        fun <T> Result<T>.toState(): Any? = this.getOrElse { CompletedExceptionally(it) }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
