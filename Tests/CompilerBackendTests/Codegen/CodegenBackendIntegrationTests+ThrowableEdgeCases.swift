@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenThrowableSuppressedExceptionsProperty() throws {
        let source = """
        fun main() {
            val primary = RuntimeException("primary")
            primary.addSuppressed(IllegalStateException("suppressed1"))
            primary.addSuppressed(IllegalArgumentException("suppressed2"))

            val suppressed = primary.suppressedExceptions
            println(suppressed.size)
            println(suppressed[0].message)
            println(suppressed[1].message)
        }
        """

        try assertKotlinOutput(source, moduleName: "ThrowableSuppressedExceptionsRuntime", expected: "2\nsuppressed1\nsuppressed2\n")
    }

    // Regression test: string template interpolation ("$e") and the `+` concatenation
    // operator lower to kk_any_to_string, which used to fall through to printing the
    // raw pointer bit pattern for a caught Throwable instead of matching println(e)'s
    // output, because runtimeElementToString (unlike runtimeRenderAnyForPrint, used by
    // println) had no RuntimeThrowableBox case.
    //
    // Constructing IllegalStateException(...) now routes through its type-specific
    // constructor bridge, so the typed RuntimeThrowableBox adds the exception name
    // to rendered output. What this test guards is that all three conversions ($e,
    // +, println) stay in lockstep and none of them regresses to printing a raw pointer.
    func testCodegenCaughtThrowableStringConversionMatchesPrintln() throws {
        let source = """
        fun main() {
            try {
                throw IllegalStateException("existing type test")
            } catch (e: IllegalStateException) {
                println("interp existing: $e")
                println("plus existing: " + e)
                println(e)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ThrowableStringTemplateConcatIllegalState",
            expected:
                """
                interp existing: Throwable(IllegalStateException: existing type test)
                plus existing: Throwable(IllegalStateException: existing type test)
                Throwable(IllegalStateException: existing type test)
                """ + "\n"
        )
    }

    // Same regression as above, exercised through a different pre-existing exception
    // type (ArithmeticException raised by integer division by zero) to confirm the
    // fix is general and not tied to IllegalStateException specifically.
    func testCodegenCaughtArithmeticExceptionStringConversionMatchesPrintln() throws {
        let source = """
        fun main() {
            val n = 1
            val zero = 0
            try {
                println(n / zero)
            } catch (e: ArithmeticException) {
                println("interp arith: $e")
                println("plus arith: " + e)
                println(e)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ThrowableStringTemplateConcatArithmetic",
            expected:
                """
                interp arith: Throwable(ArithmeticException: / by zero)
                plus arith: Throwable(ArithmeticException: / by zero)
                Throwable(ArithmeticException: / by zero)
                """ + "\n"
        )
    }

    // KSP-616: TODO() is a bundled Kotlin declaration throwing NotImplementedError,
    // which must stay catchable both as its own type and as its Error supertype.
    func testCodegenTodoThrowsCatchableNotImplementedError() throws {
        let source = """
        fun main() {
            try {
                TODO()
            } catch (e: NotImplementedError) {
                println(e.message)
            }
            try {
                TODO("later")
            } catch (e: Error) {
                println(e.message)
            }
            try {
                TODO("rendered")
            } catch (e: Throwable) {
                println(e)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TodoNotImplementedError",
            expected:
                """
                An operation is not implemented.
                An operation is not implemented: later
                Throwable(NotImplementedError: An operation is not implemented: rendered)
                """ + "\n"
        )
    }
}
