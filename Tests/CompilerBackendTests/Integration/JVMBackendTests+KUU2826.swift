#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func labeledBreakAndContinueTargetOuterLoops(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                loop@ for (i in 1..3) {
                    for (j in 1..3) { if (i * j == 4) break@loop }
                }
                println("done")

                var visits = 0
                outer@ for (i in 1..3) {
                    for (j in 1..3) {
                        visits += 1
                        if (j == 1) continue@outer
                    }
                }
                println(visits)
            }
            """, expected: "done\n3\n", mode: mode, root: root)
        }
    }
}
#endif
