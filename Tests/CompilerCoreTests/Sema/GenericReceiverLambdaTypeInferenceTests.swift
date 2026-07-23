#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-CAP-008: generic receiver `T.() -> Unit` lambdas must be type-checked
/// with the concrete call-site receiver type substituted for `T`, so that
/// unqualified member access in the lambda body resolves against the actual
/// receiver and assignments to `var` properties do not trigger a false-positive
/// `KSWIFTK-SEMA-0014`.
@Suite
struct GenericReceiverLambdaTypeInferenceTests {

    @Test func testGenericExtensionReceiverLambdaResolvesMembersWithoutReassignError() throws {
        let source = """
        class MutableBox<T> {
            var myValue: T? = null
        }

        fun <T> T.apply2(block: T.() -> Unit): T {
            block()
            return this
        }

        fun useApply2(): MutableBox<Int> = MutableBox<Int>().apply2 { myValue = 42 }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Generic receiver lambda T.() -> Unit should resolve myValue without SEMA-0014, got: \\(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testGenericReceiverLambdaDoesNotFallBackToLexicalScopeForProperty() throws {
        // Regression: without substituting the receiver type parameter, the
        // compiler would fail member lookup, fall back to the top-level `val`,
        // and emit a false-positive SEMA-0014.
        let source = """
        val myValue: String = "lexical"

        class MutableBox<T> {
            var myValue: T? = null
        }

        fun <T> T.apply2(block: T.() -> Unit): T {
            block()
            return this
        }

        fun useApply2(): MutableBox<Int> = MutableBox<Int>().apply2 { myValue = 42 }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Generic receiver lambda should shadow lexical myValue with receiver member, got: \\(errors)"
        )
    }

    @Test func testGenericRunWithReturnTypeResolvesMembers() throws {
        let source = """
        class MutableBox<T> {
            var myValue: T? = null
        }

        fun <T, R> T.run2(block: T.() -> R): R = block()

        fun useRun2(): Int = MutableBox<Int>().run2 {
            myValue = 100
            myValue ?: 0
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Generic receiver lambda T.() -> R should resolve myValue and return type, got: \\(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testWithInferredReceiverFromArgumentStillWorks() throws {
        let source = """
        class MutableBox<T> {
            var myValue: T? = null
        }

        fun <T, R> with2(receiver: T, block: T.() -> R): R = receiver.block()

        fun useWith2(): Int {
            val box = MutableBox<Int>()
            return with2(box) {
                myValue = 99
                myValue ?: 0
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "with(receiver, T.() -> R) should resolve receiver members, got: \\(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testConcreteReceiverLambdaStillWorks() throws {
        let source = """
        class ConcreteBox {
            var myValue: Int? = null
        }

        fun ConcreteBox.apply2(block: ConcreteBox.() -> Unit): ConcreteBox {
            block()
            return this
        }

        fun useConcrete(): ConcreteBox = ConcreteBox().apply2 { myValue = 42 }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Concrete receiver lambda should still resolve members, got: \\(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
