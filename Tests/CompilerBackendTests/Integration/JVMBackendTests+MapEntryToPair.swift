#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func mapEntryToPairInlinesOnOwnAndOfficialRuntimes() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                val values = linkedMapOf("a" to 1, "b" to 2)
                for (entry in values.entries) {
                    println(entry.toPair())
                }
                val pair: Pair<String, Int> = values.entries.first().toPair()
                println(pair.first + pair.second)
                val nullable = mapOf<String?, Int?>(Pair(null, null))
                println(nullable.entries.first().toPair())
                val mutable = mutableMapOf("x" to 10)
                val entry = mutable.entries.first()
                entry.setValue(11)
                println(entry.toPair())
            }
            """, expected: "(a, 1)\n(b, 2)\na1\n(null, null)\n(x, 11)\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
