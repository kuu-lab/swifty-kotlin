#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledArrayFilterNotNullPreservesNonNullElements() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun main() {
                println(arrayOf(null, "one", null, "one", "two").filterNotNull())
                println(arrayOf<Int?>(null, 0, 2, null).filterNotNull())
                println(arrayOfNulls<String>(2).filterNotNull())
                println(emptyArray<String?>().filterNotNull())
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "[one, one, two]\n[0, 2]\n[]\n[]\n")
        }
    }
}
#endif
