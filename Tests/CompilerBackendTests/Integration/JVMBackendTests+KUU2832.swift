#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu2832IterableWithIndexDestructuring(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                for ((i, v) in listOf("a", "b").withIndex()) print("$i=$v ")
                println()
                val indexed = listOf("c", "d").withIndex()
                for ((i, v) in indexed) print("$i=$v ")
                println()
            }
            """, expected: "0=a 1=b \n0=c 1=d \n", mode: mode, root: root)
        }
    }
}
#endif
