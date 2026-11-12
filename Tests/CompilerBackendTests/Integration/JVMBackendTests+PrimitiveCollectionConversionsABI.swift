#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledPrimitiveCollectionConversionsLinkAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                println(listOf<Float>(1.5f, -0.0f, Float.NaN).toFloatArray().contentToString())
                println(listOf<Byte>(-128, 127).toByteArray().contentToString())
                println(listOf(1L, Long.MAX_VALUE).toLongArray().contentToString())
                println(emptyList<Float>().toFloatArray().size)
            }
            """
            try source.write(to: root.appendingPathComponent("Conversions.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Conversions.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "ConversionsKt"])
            #expect(run.stdout == "[1.5, -0.0, NaN]\n[-128, 127]\n[1, 9223372036854775807]\n0\n")
        }
    }
}
#endif
