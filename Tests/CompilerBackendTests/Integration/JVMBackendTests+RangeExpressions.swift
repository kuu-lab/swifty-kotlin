#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
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
