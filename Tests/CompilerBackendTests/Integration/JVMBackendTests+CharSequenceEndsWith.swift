#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledCharSequenceEndsWithUsesDefaultAndExplicitArguments() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun main() {
                val suffix: CharSequence = StringBuilder(".xml")
                val filename: CharSequence = StringBuilder("vector.XML")
                println(filename.endsWith(suffix))
                println(filename.endsWith(suffix, ignoreCase = true))
                println(filename.endsWith(""))
                println("x".let { it as CharSequence }.endsWith(filename))
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "false\ntrue\ntrue\nfalse\n")
        }
    }
}
#endif
