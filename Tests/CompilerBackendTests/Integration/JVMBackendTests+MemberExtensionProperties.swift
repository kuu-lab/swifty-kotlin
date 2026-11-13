#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func memberExtensionPropertiesKeepBothReceivers() throws {
        try withWorkspace { root in
            let result = try compile("""
            class Formatter(private val prefix: String) {
                private var stored = 0
                private val String.label get() = prefix + this
                private var String.total: Int
                    get() = prefix.length + length
                    set(value) { stored = value + length }
                private val String.display get() = label + "=" + total

                fun format(text: String?): String? = text?.display
                fun update(text: String) {
                    text.total += 4
                    println(stored)
                }
            }

            fun main() {
                val formatter = Formatter("> ")
                println(formatter.format("abc"))
                println(formatter.format(null))
                formatter.update("abc")
            }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java([
                "-cp", root.appendingPathComponent("hello.jar").path + ":" + m11Runtime(), "HelloKt",
            ])
            #expect(execution.stdout == "> abc=5\nnull\n12\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
