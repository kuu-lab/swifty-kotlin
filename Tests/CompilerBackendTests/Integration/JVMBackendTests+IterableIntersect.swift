#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledIterableIntersectKeepsReceiverOrder() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun main() {
                val left: Iterable<Int?> = listOf(5, null, 2, 5, 1)
                val right: Iterable<Int?> = Iterable { listOf(2, 5, null).iterator() }
                println(left intersect right)
                println(right intersect left)
                println(left intersect emptyList())
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "[5, null, 2]\n[2, 5, null]\n[]\n")
        }
    }
}
#endif
