#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendTypealiasUsageTests {

    @Test
    func testCodegenTypealiasUsageExecutableRunsCollectionStringPredicate() throws {
        let source = """
        typealias StringList = List<String>
        typealias Predicate<T> = (T) -> Boolean
        typealias IntPair = Pair<Int, Int>

        fun main() {
            val names: StringList = listOf("Alice", "Bob", "Charlie")
            println(names.filter { it.length > 3 })
            val pred: Predicate<String> = { it.length > 3 }
            println(pred("Hello"))
            val pair: IntPair = IntPair(1, 2)
            println("${pair.first},${pair.second}")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TypealiasUsageRuntime",
            expected:
                """
                [Alice, Charlie]
                true
                1,2
                """ + "\n"
        )
    }
}
#endif
