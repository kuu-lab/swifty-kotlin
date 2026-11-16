#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledIterableRemoveAllUsesMutableIterator() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun main() {
                val values = mutableListOf(1, 2, 3, 2, 4)
                val iterable: MutableIterable<Int> = values
                println(iterable.removeAll { it % 2 == 0 })
                println(values)
                println(iterable.removeAll { false })
                println(values)
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "true\n[1, 3]\nfalse\n[1, 3]\n")
        }
    }
}
#endif
