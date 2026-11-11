#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func emptyCollectionFactoriesUsePublicABI(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                println(emptyList<Int>() === listOf<Int>())
                println(emptySet<Int>() === setOf<Int>())
                println(emptyMap<Int, Int>() === mapOf<Int, Int>())
            }
            """, expected: "true\ntrue\ntrue\n", mode: mode, root: root)
        }
    }
}
#endif
