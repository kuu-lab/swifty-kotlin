#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// BUG-164: callable references must be eligible for SAM conversion when the
/// expected type is a functional interface parameter of a function call.
@Suite
struct CallableRefSamConversionTests {

    @Test func testCallableRefPassedToFunInterfaceParameter() throws {
        let source = """
        fun interface Transformer {
            fun transform(s: String): Int
        }

        fun transformImpl(s: String): Int = s.length

        fun apply(t: Transformer): Int = t.transform("hello")

        fun main() {
            println(apply(::transformImpl))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Callable reference passed to a fun interface parameter should type-check, got: \(errors)"
        )
    }

    @Test func testCallableRefSamConstructor() throws {
        let source = """
        fun interface Transformer {
            fun transform(s: String): Int
        }

        fun transformImpl(s: String): Int = s.length

        fun main() {
            val t = Transformer(::transformImpl)
            println(t.transform("hello"))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Callable reference in a SAM constructor should type-check, got: \(errors)"
        )
    }

    /// KUU-3203: the SAM constructor argument may be any expression producing
    /// a function value, including calls on callable references like
    /// `::prop.get()` — not only lambda literals or bare references.
    @Test func testSamConstructorPropertyReferenceGetCall() throws {
        let source = """
        fun interface SamInterface {
            fun accept(): String
        }

        val prop: () -> String = { "OK" }

        fun main() {
            val sam = SamInterface(::prop.get())
            println(sam.accept())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "SAM constructor with a ::prop.get() argument should type-check, got: \(errors)"
        )
    }

    /// KUU-3203: `SamInterface((::A)())` — an invoked constructor reference
    /// whose result is a nominal FunctionN subtype is SAM-convertible
    /// (upstream callableReference/function/
    /// extensionFunctionAsASuperTypePassToSAMInterface).
    @Test func testSamConstructorInvokedConstructorReference() throws {
        let source = """
        fun interface SamInterface {
            fun Int.accept(): String
        }

        class A: Int.() -> String {
            override fun invoke(p1: Int): String {
                return "O"
            }
        }

        val a = SamInterface((::A)())

        fun main() {
            with(a) {
                println(1.accept())
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "SAM constructor with a (::A)() argument should type-check, got: \(errors)"
        )
    }

    /// KUU-3203: a stored function value converts for a SAM member that has an
    /// extension receiver — the argument binds the SAM function type, not the
    /// interface type.
    @Test func testSamConstructorFunctionValueReceiverSam() throws {
        let source = """
        fun interface SamInterface {
            fun Int.accept(): String
        }

        fun main() {
            val f: Int.() -> String = { "v" }
            val sam = SamInterface(f)
            with(sam) {
                println(1.accept())
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "SAM constructor with a function-value argument for a receiver SAM should type-check, got: \(errors)"
        )
    }

    /// KUU-3203: a function value incompatible with the SAM member signature
    /// must not be silently converted.
    @Test func testSamConstructorFunctionValueMismatchRejected() throws {
        let source = """
        fun interface SamInterface {
            fun accept(a: Int, b: Int): String
        }

        fun main() {
            val f: (Int) -> String = { "x" }
            val sam = SamInterface(f)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            !errors.isEmpty,
            "SAM constructor with an incompatible function value should fail type-checking"
        )
    }
}
#endif
