#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func tailrecCallsBecomeLoopsWithDefaultsAndArgumentSnapshots(mode: EmitMode) throws {
        try assertJVM("""
        tailrec fun count(n: Int, sum: Long = 0L): Long =
            if (n == 0) sum else count(n - 1, sum + n)
        tailrec fun rotate(n: Int, a: Int, b: Int): Int {
            if (n == 0) return a * 10 + b
            return rotate(n - 1, b, a)
        }
        var defaults = 0
        fun observed(n: Int): Int { defaults++; return n }
        tailrec fun reset(n: Int, value: Int = observed(n)): Int =
            if (n == 0) value else reset(n - 1)
        tailrec fun Int.descend(): Int = if (this == 0) this else (this - 1).descend()
        fun main() {
            println(count(100000))
            println(rotate(100001, 1, 2))
            println(reset(3))
            println(defaults)
            println(100000.descend())
        }
        """, "5000050000\n21\n0\n4\n0\n", mode: mode)
    }
}
#endif
