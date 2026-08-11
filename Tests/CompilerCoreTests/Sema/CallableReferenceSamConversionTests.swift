#if canImport(Testing)
@testable import CompilerCore
import Testing

/// BUG-164: A callable reference passed to a parameter whose type is a
/// `fun interface` must be SAM-converted, just like an equivalent lambda
/// literal.  Previously Sema left the reference as a bare function type,
/// so overload resolution rejected the call.
@Suite
struct CallableReferenceSamConversionTests {

    @Test func testCallableRefPassedToFunInterfaceParameter() throws {
        let source = """
        fun interface IntOp { fun apply(a: Int, b: Int): Int }

        fun useOp(o: IntOp): Int = o.apply(10, 4)

        fun myCompare(a: Int, b: Int): Int = a - b

        fun main() {
            println(useOp(::myCompare))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Callable reference passed to a fun-interface parameter should type-check, got: \\(errors)"
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
