#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledHashMapFactoryReturnsTheHashMapAbi() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun main() {
                val values = hashMapOf("x" to 1, null to 2, "x" to 3)
                println(values.javaClass.name)
                println(values["x"])
                println(values[null])
                println(hashMapOf<String, Int>().size)
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "java.util.HashMap\n3\n2\n0\n")
        }
    }
}
#endif
