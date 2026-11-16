#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledMapAsSequenceReadsLiveEntries() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun main() {
                val values = linkedMapOf("first" to 1, "second" to 2)
                val entries = values.asSequence()
                values.put("third", 3)
                println(entries.joinToString { it.key + "=" + it.value })
                values.remove("second")
                println(entries.map { it.key }.toList())
                println(emptyMap<String, Int>().asSequence().count())
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "first=1, second=2, third=3\n[first, third]\n0\n")
        }
    }
}
#endif
