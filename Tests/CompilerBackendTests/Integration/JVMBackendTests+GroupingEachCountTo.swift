#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func groupingEachCountToRunsAgainstOfficialAndOwnRuntime() throws {
        let source = #"""
        class FirstLetterGrouping(val values: List<String>) : Grouping<String, String> {
            override fun sourceIterator(): Iterator<String> = values.iterator()
            override fun keyOf(element: String): String = element.substring(0, 1)
        }

        fun main() {
            val grouping = FirstLetterGrouping(listOf("apple", "banana", "avocado"))
            println(grouping.eachCountTo(mutableMapOf("a" to 10)))
        }
        """#

        try withWorkspace { root in
            try runRuntimeParity(source, expected: "{a=12, b=1}\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
