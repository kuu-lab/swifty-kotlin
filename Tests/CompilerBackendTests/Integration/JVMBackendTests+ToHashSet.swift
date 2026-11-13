#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func iterableToHashSetLinksAgainstOwnStdlib() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                println(emptyList<String>().toHashSet().isEmpty())
                val values = mutableListOf("first", null, "first")
                val set: HashSet<String?> = values.toHashSet()
                values.add("later")
                println(set.contains(null))
                println(set.contains("later"))
                println(set.add("first"))
                println(set.add("second"))
                println(set.size)
            }
            """, expected: "true\ntrue\nfalse\nfalse\ntrue\n3\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
