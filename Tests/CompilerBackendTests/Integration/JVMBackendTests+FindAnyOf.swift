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

    @Test
    func findAnyOfMatchesKotlinSearchBoundariesWithBundledRuntime() throws {
        let source = #"""
        fun main() {
            val text = "abc"
            val builder = StringBuilder("abc")
            val multiple = listOf("", "z")
            val single = listOf("")
            println(text.indexOfAny(multiple, startIndex = 4))
            println(text.findAnyOf(multiple, startIndex = 4))
            println(builder.indexOfAny(multiple, startIndex = 4))
            println(builder.findAnyOf(multiple, startIndex = 4))
            println(text.lastIndexOfAny(multiple, startIndex = 3))
            println(text.findLastAnyOf(multiple, startIndex = 3))
            println(builder.lastIndexOfAny(multiple, startIndex = 3))
            println(builder.findLastAnyOf(multiple, startIndex = 3))
            println(text.indexOfAny(single, startIndex = 4))
            println(text.findAnyOf(single, startIndex = 4))
            println(builder.indexOfAny(single, startIndex = 4))
            println(builder.findAnyOf(single, startIndex = 4))
            println(text.lastIndexOfAny(single, startIndex = 3))
            println(text.findLastAnyOf(single, startIndex = 3))
            println(builder.lastIndexOfAny(single, startIndex = 3))
            println(builder.findLastAnyOf(single, startIndex = 3))

            val supplementary = listOf("𐐨")
            val capital = "𐐀"
            val capitalBuilder = StringBuilder(capital)
            println(capital.indexOfAny(supplementary, ignoreCase = true))
            println(capital.lastIndexOfAny(supplementary, ignoreCase = true))
            println(capital.findAnyOf(supplementary, ignoreCase = true))
            println(capital.findLastAnyOf(supplementary, ignoreCase = true))
            println(capitalBuilder.indexOfAny(supplementary, ignoreCase = true))
            println(capitalBuilder.lastIndexOfAny(supplementary, ignoreCase = true))
            println(capitalBuilder.findAnyOf(supplementary, ignoreCase = true))
            println(capitalBuilder.findLastAnyOf(supplementary, ignoreCase = true))
        }
        """#
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar, includeJVMRuntime: true)
            let diagnostics = result.1.map { diagnostic in
                let range = diagnostic.primaryRange.map { "\($0.start.offset)..<\($0.end.offset)" } ?? "unknown"
                return "\(range): \(diagnostic.message)"
            }.joined(separator: "\n")
            try #require(result.0 == 0, "\(diagnostics)")
            let execution = try java(["-jar", root.appendingPathComponent("hello.jar").path])
            #expect(execution.stdout == "-1\nnull\n-1\nnull\n2\n(2, )\n2\n(2, )\n3\n(3, )\n-1\nnull\n3\n(3, )\n2\n(2, )\n0\n0\n(0, 𐐨)\n(0, 𐐨)\n-1\n-1\nnull\nnull\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
