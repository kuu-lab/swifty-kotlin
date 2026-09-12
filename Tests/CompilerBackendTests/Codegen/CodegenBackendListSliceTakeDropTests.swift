#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendListSliceTakeDropTests {

    // Regression for KSP-427: List take/drop/slice family must resolve to
    // bundled Kotlin source functions, not to stale runtime bridges or
    // unresolved external symbols.
    @Test
    func testCodegenListSliceTakeDropFamily() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3, 4, 5)
            println(list.take(3))
            println(list.drop(2))
            println(list.takeLast(2))
            println(list.dropLast(2))
            println(list.takeWhile { it < 3 })
            println(list.dropWhile { it < 3 })
            println(list.takeLastWhile { it > 3 })
            println(list.dropLastWhile { it > 3 })
            println(list.slice(1..3))
            println(list.slice(listOf(0, 2, 4)))
            println(list.subList(1, 4))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListSliceTakeDropRegression",
            expected: """
            [1, 2, 3]
            [3, 4, 5]
            [4, 5]
            [1, 2, 3]
            [1, 2]
            [3, 4, 5]
            [4, 5]
            [1, 2, 3]
            [2, 3, 4]
            [1, 3, 5]
            [2, 3, 4]

            """
        )
    }
}
#endif
