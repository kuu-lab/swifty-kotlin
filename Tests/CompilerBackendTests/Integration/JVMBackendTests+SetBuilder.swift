#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func setBuilderLinksAgainstOwnStdlibAndFreezesResult() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                println(buildSet<String> {})
                val values = buildSet<String?>(4) {
                    add("second")
                    addAll(listOf(null, "first", "second"))
                }
                println(values)
                try {
                    (values as MutableSet<String?>).add("third")
                } catch (_: UnsupportedOperationException) {
                    println("frozen")
                }
                try {
                    buildSet<String>(-1) {}
                } catch (_: IllegalArgumentException) {
                    println("negative capacity")
                }
            }
            """, expected: "[]\n[second, null, first]\nfrozen\nnegative capacity\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
