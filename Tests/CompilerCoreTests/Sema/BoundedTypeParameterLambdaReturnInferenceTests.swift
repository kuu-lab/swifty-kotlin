#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-410 / BUG-170: a lone type parameter with an upper bound (`R : Any`)
/// inferred purely from a nullable-returning lambda body used to fail with
/// KSWIFTK-TYPE-0001. The lambda body was locally constrained against the
/// callee's own `R?`, which nothing but `R` itself is a subtype of; the check
/// now uses the parameter's upper bound instead.
@Suite
struct BoundedTypeParameterLambdaReturnInferenceTests {
    @Test func testBoundedTypeParameterInfersFromNullableLambdaBody() throws {
        let source = """
        fun <R : Any> String.firstTransformed(transform: (Char) -> R?): R? {
            var i = 0
            while (i < length) {
                val transformed = transform(this[i])
                if (transformed != null) return transformed
                i++
            }
            return null
        }

        fun main() {
            println("abc".firstTransformed { c -> if (c == 'b') 1 else null })
            println("abc".firstTransformed { c -> if (c == 'b') c else null })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-INFER", in: ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func testBoundedTypeParameterStillRejectsBodyOutsideUpperBound() throws {
        let source = """
        fun <R : Number> pick(transform: (Int) -> R): R = transform(1)

        fun main() {
            println(pick { "not a number" })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected a diagnostic for a body outside R's upper bound")
        }
    }
}
#endif
