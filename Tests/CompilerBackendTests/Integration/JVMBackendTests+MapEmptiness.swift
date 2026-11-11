#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mapIsNotEmptyMatchesKotlinc(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val maps: List<Map<String, String?>> = listOf(emptyMap(), mapOf("key" to null))
                println(maps.filter { it.isNotEmpty() }.size)
                val empty: Map<*, *> = maps[0]
                println(empty.isNotEmpty())
                val populated = maps[1]
                println(populated.isNotEmpty())
                val predicate: () -> Boolean = populated::isNotEmpty
                println(predicate())
            }
            """, expected: "1\nfalse\ntrue\ntrue\n", mode: mode, root: root)
        }
    }
}
#endif
