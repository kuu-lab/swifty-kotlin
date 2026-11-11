#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4532ArrayWithIndex(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                for ((index, value) in intArrayOf(10, 20, 30).withIndex()) {
                    println(index + value)
                }
                val indexed = intArrayOf(1, 2).withIndex()
                for ((index, value) in indexed) println("$index:$value")
                val strings = arrayOf("a", "b")
                for ((index, value) in strings.withIndex()) println("$index=$value")
            }
            """, expected: "10\n21\n32\n0:1\n1:2\n0=a\n1=b\n", mode: mode, root: root)
        }
    }
}
#endif
