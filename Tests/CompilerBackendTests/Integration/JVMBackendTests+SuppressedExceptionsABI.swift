#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func suppressedExceptionsABIHandlesSelfAndPreservesOrder() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            fun main() {
                val error = IllegalStateException("primary")
                println(error.suppressedExceptions.size)
                error.addSuppressed(error)
                error.addSuppressed(IllegalStateException("first"))
                error.addSuppressed(IllegalArgumentException("second"))
                println(error.suppressedExceptions.joinToString(",") { it.message ?: "" })
            }
            """
            try source.write(to: root.appendingPathComponent("SuppressedProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["SuppressedProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", app.path + ":" + official, "SuppressedProbeKt"])
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "SuppressedProbeKt"])
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif
