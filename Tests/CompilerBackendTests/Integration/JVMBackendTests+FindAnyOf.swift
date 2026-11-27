#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func findAnyOfAndFindLastAnyOfMatchKotlinRuntime(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                val text = "こんにちは世界こんにちは"
                val needles = listOf("世界", "こんにちは")
                println(text.indexOfAny(charArrayOf('世', '界')))
                println(text.lastIndexOfAny(charArrayOf('世', '界')))
                println(text.indexOfAny(needles))
                println(text.lastIndexOfAny(needles))
                println(text.findAnyOf(needles))
                println(text.findLastAnyOf(needles))
                println("abc".findAnyOf(listOf("x", "bc"), startIndex = 0))
                println("abc".findAnyOf(listOf("ABC"), ignoreCase = true))
                println("abc".findLastAnyOf(listOf("b", "C"), ignoreCase = true))
                println("abc".findLastAnyOf(listOf("a"), startIndex = 2, ignoreCase = false))
            }
            """#, expected: "5\n6\n0\n7\n(0, こんにちは)\n(7, こんにちは)\n(1, bc)\n(0, ABC)\n(2, C)\n(0, a)\n", mode: mode, root: root)
        }
    }
}
#endif
