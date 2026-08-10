@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    /// KSP-441: `List.reduceRightIndexed` is an inline HOF whose lambda body
    /// must not be inlined as an ordinary inline function. Doing so splices a
    /// pre-ABI body into the caller and loses the boxing/unboxing information
    /// needed for primitive lambda parameters, producing garbage results.
    func testCodegenListReduceRightIndexedInlineLambdaStaysCorrectlyBoxed() throws {
        let source = """
        fun main() {
            val values: List<Int> = listOf(1, 2, 3)

            println(values.reduceRightIndexed { index, value, acc ->
                index * 100 + value * 10 + acc
            })
            println(listOf(7).reduceRightIndexed { index, value, acc ->
                index + value + acc
            })

            try {
                println(emptyList<Int>().reduceRightIndexed { index, value, acc ->
                    index + value + acc
                })
            } catch (e: Throwable) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListReduceRightIndexedRuntime", expected: "133\n7\nempty\n")
    }
}
