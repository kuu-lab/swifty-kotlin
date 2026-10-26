@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct InfixCallLambdaImplicitLabelSemaTests {
    @Test
    func infixLambdaReturnUsesImplicitCalleeLabel() throws {
        let ctx = makeContextFromSource("""
        fun test(x: Int): Int {
            x myMap { return@myMap }
            return 0
        }

        fun myMap(x: Int): Int {
            x myMap { return@myMap }
            return 0
        }

        infix fun Int.myMap(block: () -> Unit) {}

        fun box(): String {
            test(0)
            myMap(0)
            return "OK"
        }
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected both infix lambda returns to resolve locally, got: \(errors)")
    }

    @Test
    func infixLambdaStillRejectsReturnToNonInlineEnclosingFunction() throws {
        let ctx = makeContextFromSource("""
        infix fun Int.myMap(block: () -> Unit) {}

        fun enclosing() {
            0 myMap { return@enclosing }
        }
        """)

        try runSema(ctx)

        let diagnostic = ctx.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-SEMA-0042"
                && $0.message.contains("cannot cross a non-inline")
        }
        #expect(diagnostic != nil, "Expected the non-local return rejection, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitLambdaLabelStillOverridesInfixCalleeLabel() throws {
        let ctx = makeContextFromSource("""
        infix fun Int.myMap(block: () -> Unit) {}

        fun explicitLabelControl() {
            0 myMap action@{ return@action }
        }
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected the explicit lambda label to remain valid, got: \(errors)")
    }
}
