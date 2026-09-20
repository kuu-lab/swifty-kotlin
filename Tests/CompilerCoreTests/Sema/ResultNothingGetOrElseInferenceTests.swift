#if canImport(Testing)
@testable import CompilerCore
import Testing

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

            assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }
}
#endif
