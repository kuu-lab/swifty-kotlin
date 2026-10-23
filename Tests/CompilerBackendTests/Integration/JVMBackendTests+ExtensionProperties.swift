#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func topLevelExtensionPropertiesReadAndWrite(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            val Int.dbl: Int get() = this * 2
            val String.lastC: Char get() = this[length - 1]
            var StringBuilder.dbl: Int
                get() = length
                set(v) { setLength(v) }
            fun Int.dblAgain(): Int = dbl
            fun main() {
                println(3.dbl)
                println("abc".lastC)
                println(3.dblAgain())
                val builder = StringBuilder("abcdef")
                builder.dbl = 3
                println(builder.dbl)
            }
            """, expected: "6\nc\n6\n3\n", mode: mode, root: root)
        }
    }
}
#endif
