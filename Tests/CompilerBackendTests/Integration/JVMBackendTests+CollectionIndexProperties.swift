#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionIndexPropertiesUseKotlinGetters(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val values = listOf("first", "second")
                val collection: Collection<String> = values
                println(collection.indices)
                println(values.lastIndex)
                for (i in values.indices) println(values[i])
                println(emptyList<String>().indices.isEmpty())
            }
            """, expected: "0..1\n1\nfirst\nsecond\ntrue\n", mode: mode, root: root)
        }
    }
}
#endif
