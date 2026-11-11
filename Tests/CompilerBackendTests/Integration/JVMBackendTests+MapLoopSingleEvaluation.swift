#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mapForLoopEvaluatesIterableOnce(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            var calls = 0

            fun values(): Map<Int, Int> {
                calls += 1
                return mapOf(4 to 5, 6 to 7)
            }

            fun main() {
                var sum = 0
                for ((key, value) in values()) sum += key + value
                println(sum)
                println(calls)

                var entrySum = 0
                for (entry in values()) entrySum += entry.key + entry.value
                println(entrySum)
                println(calls)
            }
            """, expected: "22\n1\n22\n2\n", mode: mode, root: root)
        }
    }
}
#endif
