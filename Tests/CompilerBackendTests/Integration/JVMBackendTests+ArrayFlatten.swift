#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func arrayOfArraysFlattenLinksAgainstOwnStdlib() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                println(arrayOf(arrayOf(1, 2), arrayOf(3)).flatten())
                println(arrayOf(arrayOf(1), arrayOf(2, 3), arrayOf(4, 5, 6)).flatten())
                println(arrayOf(arrayOf("a", "b"), arrayOf("c")).flatten())
                println(arrayOf<Array<Int>>().flatten())
                println(arrayOf(arrayOf<Int>(), arrayOf(1)).flatten())
                println(arrayOf(arrayOf(1, 2), arrayOf<Int>(), arrayOf(3)).flatten())
            }
            """, expected: "[1, 2, 3]\n[1, 2, 3, 4, 5, 6]\n[a, b, c]\n[]\n[1]\n[1, 2, 3]\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
