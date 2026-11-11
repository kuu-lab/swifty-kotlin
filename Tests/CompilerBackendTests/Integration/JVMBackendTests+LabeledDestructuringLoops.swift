#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func labeledDestructuringLoopsHandleBreakContinueAndFinally(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                var sum = 0
                var finalized = 0
                outer@ for ((index, value) in listOf(10, 20, 30).withIndex()) {
                    for (j in 1..2) {
                        try {
                            if (index == 0) continue@outer
                            if (index == 2) break@outer
                            sum += value + j
                        } finally {
                            finalized += 1
                        }
                    }
                }
                println(sum)
                println(finalized)

                var mapValue = 0
                entries@ for ((key, value) in mapOf(4 to 5, 6 to 7)) {
                    for (j in 1..2) {
                        if (key == 4) continue@entries
                        mapValue += value
                        break@entries
                    }
                }
                println(mapValue)

                var arraySum = 0
                numbers@ for ((index, value) in arrayOf(0 to 10, 1 to 20, 2 to 30)) {
                    if (index == 0) continue@numbers
                    if (index == 2) break@numbers
                    arraySum += value
                }
                println(arraySum)
            }
            """, expected: "43\n4\n7\n20\n", mode: mode, root: root)
        }
    }
}
#endif
