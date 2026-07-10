@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenReifiedInlineCastFailureCaughtByCallerTryCatch() throws {
        let source = """
        inline fun <reified T> reifiedCast(value: Any?): T {
            return value as T
        }

        fun main() {
            try {
                reifiedCast<String>(42)
            } catch (e: Exception) {
                println("caught: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ReifiedInlineCastCaughtRuntime", expected: "caught: ClassCastException\n")
    }

    func testCodegenReifiedInlineCastSuccessDoesNotTriggerCatch() throws {
        let source = """
        inline fun <reified T> reifiedCast(value: Any?): T {
            return value as T
        }

        fun main() {
            try {
                println(reifiedCast<String>("hello"))
            } catch (e: Exception) {
                println("unexpected: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ReifiedInlineCastSuccessRuntime", expected: "hello\n")
    }

    func testCodegenInlineLambdaCastFailureCaughtByCallerTryCatch() throws {
        let source = """
        inline fun <T> runIt(block: () -> T): T {
            return block()
        }

        fun main() {
            try {
                runIt<String> {
                    val x: Any? = 42
                    x as String
                }
            } catch (e: ClassCastException) {
                println("caught: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "InlineLambdaCastCaughtRuntime", expected: "caught: ClassCastException\n")
    }
}
