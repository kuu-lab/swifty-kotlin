#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func multilineDelimitedBinaryExpressions(mode: EmitMode) throws {
        try assertJVM("""
        fun identity(x: Int): Int = x
        fun main() {
            println(if (1
                == 1) 7 else 9)
            println((2
                + 3
                * 4))
            println(identity(10
                - 3))
            val values = intArrayOf(10, 20)
            println(values[0
                + 1])
            val n = 1
            + 2
            println(n)
            println(identity({
                val x = 4
                + 5
                x
            }()))
        }
        """, "7\n14\n7\n20\n1\n4\n", mode: mode)
    }
}
#endif
