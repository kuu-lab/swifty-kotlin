#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// Regression coverage for implicit exceptions produced by `!!` and a cast to
// a non-null type. These operations must enter the enclosing Kotlin catch
// clause through the same thrown channel as an explicit `throw`.
@Suite
struct CodegenBackendImplicitExceptionCatchTests {

    @Test
    func testImplicitNullAndCastExceptionsAreCaught() throws {
        let source = """
        fun main() {
            try {
                val n: String? = null
                println(n!!.length)
            } catch (e: Throwable) {
                println("throwable caught " + e)
            }

            try {
                val n: String? = null
                println(n!!.length)
            } catch (e: Exception) {
                println("exception caught: " + (e is NullPointerException))
            }

            try {
                val n: String? = null
                println(n!!.length)
            } catch (e: NullPointerException) {
                println("npe caught")
            }

            try {
                val x: Any? = null
                println(x as String)
            } catch (e: Throwable) {
                println("cast null caught " + e)
            }

            try {
                throw NullPointerException("explicit")
            } catch (e: NullPointerException) {
                println(e.message)
            }

            fun f(s: String?) = s!!.length

            try {
                println(f(null))
            } catch (e: NullPointerException) {
                println("npe fn caught")
            }

            println("end")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ImplicitExceptionCatch",
            expected:
                """
                throwable caught java.lang.NullPointerException
                exception caught: true
                npe caught
                cast null caught java.lang.NullPointerException: null cannot be cast to non-null type kotlin.String
                explicit
                npe fn caught
                end
                """ + "\n"
        )
    }
}
#endif
