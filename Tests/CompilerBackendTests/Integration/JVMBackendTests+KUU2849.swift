#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu2849CollectionTakeDropVariants(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                val list = listOf(1, 2, 3)
                println(list.takeLast(2))
                println(list.takeWhile { it < 3 })
                println(list.dropWhile { it < 2 })
                println(list.dropLastWhile { it > 1 })

                val iterable: Iterable<Int> = sequenceOf(1, 2, 3).asIterable()
                println(iterable.takeWhile { it < 3 })
                println(iterable.dropWhile { it < 2 })
            }
            """#, expected: "[2, 3]\n[1, 2]\n[2, 3]\n[1]\n[1, 2]\n[2, 3]\n", mode: mode, root: root)
        }
    }
}
#endif
