@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testInlinedMapPreservesSmartCastOfAnyLambdaParameter() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val values: List<Any> = listOf(1, "ab")
                println(values.map { when (it) {
                    is Int -> it + 1
                    is String -> it.length
                    else -> 0
                } })
            }
            """,
            expectedOutput: "[2, 2]\n",
            moduleName: "InlinedMapSmartCast",
            expectedStderr: "",
            requireNoCompilerDiagnostics: true
        )
    }
}
