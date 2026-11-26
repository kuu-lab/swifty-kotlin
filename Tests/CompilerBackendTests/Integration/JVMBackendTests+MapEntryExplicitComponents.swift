#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    // Map.Entry.component1/component2 used to be declared twice for JVM consumers
    // (collections.kt and map-operators.kt), so explicit calls were ambiguous.
    @Test
    func mapEntryExplicitComponentCallsResolveOnOwnAndOfficialRuntimes() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                val values = linkedMapOf("a" to 1, "b" to 2)
                for (entry in values.entries) {
                    println(entry.component1())
                    println(entry.component2())
                }
                val (key, value) = values.entries.first()
                println("$key=$value")
            }
            """, expected: "a\n1\nb\n2\na=1\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
