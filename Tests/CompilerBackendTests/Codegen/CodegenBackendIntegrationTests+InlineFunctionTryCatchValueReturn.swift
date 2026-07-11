@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testInlineFunctionTryCatchWithMultipleCatchBodyCallsReturnsCorrectValue() throws {
        let source = """
        inline fun <reified T> reifiedCastOrNull(value: Any?): T? {
            return try {
                value as T
            } catch (e: Exception) {
                println("logged: ${e.message}")
                null
            }
        }

        fun main() {
            println(reifiedCastOrNull<String>(42))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "InlineTryCatchReifiedCastOrNull",
            expected: "logged: ClassCastException\nnull\n"
        )
    }

    func testInlineFunctionTryCatchWithSequentialCatchBodyCallsRunsAllStatements() throws {
        let source = """
        inline fun <reified T> castOrNullLogged(value: Any?): T? {
            return try {
                value as T
            } catch (e: Exception) {
                println("a")
                println("b")
                null
            }
        }

        fun main() {
            println(castOrNullLogged<String>(42))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "InlineTryCatchSequentialCatchBodyCalls",
            expected: "a\nb\nnull\n"
        )
    }
}
