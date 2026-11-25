#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct CallableReferenceSamConversionTests {

    @Test func testCallableRefPassedToFunInterfaceParameter() throws {
        let source = try diffCaseSource("callable_ref_sam_as_argument.kt", file: #filePath)

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Callable reference passed to a fun-interface parameter should type-check, got: \(errors)"
        )
    }

    @Test func testCallableRefSamConversionRejectsIncompatibleReference() throws {
        let source = """
        fun interface IntOp { fun apply(a: Int, b: Int): Int }

        fun useOp(o: IntOp): Int = o.apply(10, 4)

        fun unrelated(s: String): Int = s.length

        fun main() {
            println(useOp(::unrelated))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "A callable reference whose signature does not match the SAM method should be rejected"
        )
    }
}
#endif
