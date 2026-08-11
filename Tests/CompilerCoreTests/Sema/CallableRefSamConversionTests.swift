#if canImport(Testing)
@testable import CompilerCore
import Testing

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
            "Callable reference passed to a fun interface parameter should type-check, got: \\(errors)"
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
            "Callable reference in a SAM constructor should type-check, got: \\(errors)"
        )
    }
}
#endif
