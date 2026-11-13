#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledListRemoveAllSupportsBothAccessPatterns() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun main() {
                val arrays = java.util.Arrays.asList(1, 2, 3)
                println(arrays.removeAll { false })
                for (values in listOf(arrayListOf(1, 2, 3, 2), java.util.LinkedList(listOf(1, 2, 3, 2)))) {
                    println(values.removeAll { it == 2 })
                    println(values)
                }
                println(mutableListOf<Int>().removeAll { error("empty list") })
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "false\ntrue\n[1, 3]\ntrue\n[1, 3]\nfalse\n")
        }
    }
}
#endif
