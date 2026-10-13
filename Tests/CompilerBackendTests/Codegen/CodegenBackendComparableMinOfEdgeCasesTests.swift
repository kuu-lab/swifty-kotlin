#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendComparableMinOfEdgeCasesTests {

    @Test
    func testCodegenCompilesComparableMinOfEdgeCases() throws {
        let source = """
        fun main() {
            // 2-arg Comparable minOf
            println(minOf("banana", "apple"))

            // 3-arg Comparable minOf
            println(minOf("cherry", "apple", "banana"))

            // vararg Comparable minOf (4 args)
            println(minOf("date", "banana", "apple", "cherry"))

            // vararg with winner at start
            println(minOf("ant", "zebra", "cat"))

            // vararg with winner at end
            println(minOf("zebra", "cat", "ant"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparableMinOfEdgeCases",
            expected:
                """
                apple
                apple
                apple
                ant
                ant

                """
        )
    }
}
#endif
