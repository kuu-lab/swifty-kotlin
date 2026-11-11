#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func iterableForEachIndexedPreservesOrderAndReturns(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun firstPresent(entries: Iterable<Pair<String, String?>>): Int {
                entries.forEachIndexed { index, (key, value) ->
                    println("$index:$key")
                    if (value == null) return@forEachIndexed
                    return index
                }
                return -1
            }

            fun main() {
                println(firstPresent(emptyList()))
                println(firstPresent(listOf("empty" to null, "hit" to "yes", "skipped" to "no")))
            }
            """, expected: "-1\n0:empty\n1:hit\n1\n", mode: mode, root: root)
        }
    }
}
#endif
