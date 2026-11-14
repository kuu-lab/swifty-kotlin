#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func closeFinallyLinksPrecompiledKotlinUseAndPreservesThePrimaryException() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            import java.io.Closeable

            class Resource(private val failure: Throwable? = null) : Closeable {
                override fun close() {
                    println("close")
                    if (failure != null) throw failure
                }
            }
            fun main() {
                val missing: Resource? = null
                missing.use { println(it == null) }
                Resource().use { println("body") }
                try {
                    Resource(IllegalStateException("close failure")).use {}
                } catch (error: IllegalStateException) {
                    println(error.message)
                }
                try {
                    Resource(IllegalStateException("suppressed")).use {
                        throw IllegalArgumentException("primary")
                    }
                } catch (error: IllegalArgumentException) {
                    println(error.message)
                    println(error.suppressed[0].message)
                }
                val same = IllegalArgumentException("same")
                try {
                    Resource(same).use { throw same }
                } catch (error: IllegalArgumentException) {
                    println(error === same)
                    println(error.suppressed.size)
                }
            }
            """
            try source.write(to: root.appendingPathComponent("CloseProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["CloseProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", app.path + ":" + official, "CloseProbeKt"])
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "CloseProbeKt"])
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif
