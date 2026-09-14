#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendCollectionRunningReduceEdgeCasesTests {

    @Test func testCodegenCollectionRunningReduceUsesListRuntimeForParameterReceiver() throws {
        let source = """
        fun printReductions(values: List<Int>) {
            println(values.runningReduce { acc, value -> acc + value })
        }

        fun main() {
            printReductions(listOf(1, 2, 3))
            println(listOf<Int>().runningReduce { acc, value -> acc + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRunningReduceEdgeCases",
            expected:
                """
                [1, 3, 6]
                []
                """ + "\n"
        )
    }
}
#endif
