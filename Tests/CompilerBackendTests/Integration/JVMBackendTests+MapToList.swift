#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func mapToListLinksAgainstOwnStdlibAndPreservesEntryOrder() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                println(emptyMap<String, Int>().toList())
                val singleton = mapOf<String?, Int?>(Pair(null, null))
                println(singleton.toList())
                val values = linkedMapOf(Pair("second", 2), Pair("first", 1))
                val pairs = values.toList()
                values.put("second", 3)
                println(pairs)
                println(values.toList())
            }
            """, expected: "[]\n[(null, null)]\n[(second, 2), (first, 1)]\n[(second, 3), (first, 1)]\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
