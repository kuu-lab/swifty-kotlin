#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableReferenceUnitCoercionTests {
    @Test
    func boundBooleanReferenceCoercesInsideGenericReceiverLambda() throws {
        let source = """
        class StringSink {
            fun add(value: String): Boolean = true
        }

        fun <T> T.apply2(block: T.() -> Unit): T {
            block()
            return this
        }

        fun use(sink: StringSink): String = "oak".apply2(sink::add)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "A bound Boolean reference should adapt to a Unit block: \(errors)")
    }

    @Test
    func boundBooleanReferenceCoercesToConcreteUnitFunctionType() throws {
        let source = """
        class StringSink {
            fun add(value: String): Boolean = true
        }

        fun consume(block: String.() -> Unit) {}
        fun use(sink: StringSink) { consume(sink::add) }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test
    func storedBooleanFunctionValueDoesNotCoerceToUnit() throws {
        let source = """
        fun consume(block: (String) -> Unit) {}
        fun returnsBoolean(value: String): Boolean = true

        fun use() {
            val callback: (String) -> Boolean = ::returnsBoolean
            consume(callback)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func storedCallableReferenceValueDoesNotCoerceToUnit() throws {
        let source = """
        fun consume(block: String.() -> Unit) {}
        fun returnsBoolean(value: String): Boolean = true

        fun use() {
            val callback = ::returnsBoolean
            consume(callback)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
#endif
