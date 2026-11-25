#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledMapWithDefaultKeepsTheKotlinAbi() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun main() {
                val readOnly = mapOf("a" to 1, "b" to 2).withDefault { key -> key.length }
                println(readOnly.getValue("a"))
                println(readOnly.getValue("zzzz"))
                println(readOnly["zzzz"])
                println(readOnly.size)
                println(readOnly)

                val mutable = mutableMapOf("x" to 1).withDefault { 7 }
                println(mutable.getValue("q"))
                mutable["q"] = 9
                println(mutable.getValue("q"))
                println(mutable)

                val missing: Map<String, Int>? = null
                println(missing.orEmpty().size)
                println(readOnly.orEmpty().size)

                val delegated by emptyMap<String, Int>().withDefault { key -> key.length }
                println(delegated)
                var delegatedMutable by mutableMapOf<String, Int>().withDefault { 20 }
                println(delegatedMutable)
                delegatedMutable = 21
                println(delegatedMutable)

                val source = mutableMapOf("k" to 1)
                val readOnlySource: Map<String, Int> = source
                val guarded = readOnlySource.withDefault { 0 } as java.util.AbstractMap<String, Int>
                try { guarded.clear() } catch (e: UnsupportedOperationException) { println("clear rejected") }
                try { guarded.remove("k") } catch (e: UnsupportedOperationException) { println("remove rejected") }
                println(source.size)
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "1\n4\nnull\n2\n{a=1, b=2}\n7\n9\n{x=1, q=9}\n0\n2\n9\n20\n21\nclear rejected\nremove rejected\n1\n")
        }
    }
}
#endif
