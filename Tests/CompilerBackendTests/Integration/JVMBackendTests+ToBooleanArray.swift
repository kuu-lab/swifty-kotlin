#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func collectionToBooleanArrayLinksAgainstOwnStdlib() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                println(emptyList<Boolean>().toBooleanArray().size)
                val flags = mutableListOf(true, false, true)
                val array = flags.toBooleanArray()
                flags[0] = false
                println(array[0])
                println(array[1])
                println(array[2])
            }
            """, expected: "0\ntrue\nfalse\ntrue\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
