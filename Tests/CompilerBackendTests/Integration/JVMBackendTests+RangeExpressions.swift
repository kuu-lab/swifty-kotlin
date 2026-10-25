#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func steppedRangeAndProgressionExpressions(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                println((1..10 step 2).toList())
                println((1..10).step(3).toList())
                println((10 downTo 1).step(3).toList())
                println((1L..6L step 2L).toList())
                println(('a'..'f' step 2).toList())
            }
            """, expected: "[1, 3, 5, 7, 9]\n[1, 4, 7, 10]\n[10, 7, 4, 1]\n[1, 3, 5]\n[a, c, e]\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func materializedLongAndCharRangeExpressions(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                println(('a'..'e').toList())
                println((1L..5L).toList())
                val chars: CharRange = 'x'..'z'
                val longs: LongRange = 7L..9L
                println(chars.toList())
                println(longs.toList())
            }
            """, expected: "[a, b, c, d, e]\n[1, 2, 3, 4, 5]\n[x, y, z]\n[7, 8, 9]\n", mode: mode, root: root)
        }
    }
}
#endif
