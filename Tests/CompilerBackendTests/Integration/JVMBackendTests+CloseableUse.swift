#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func closeableUseSupportsNonLocalReturnsAndSuppressedFailures() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            import java.io.Closeable

            class Resource(private val failure: Throwable?) : Closeable {
                override fun close() {
                    println("close")
                    if (failure != null) throw failure
                }
            }

            fun early(): Int {
                Resource(null).use { return 42 }
            }

            fun main() {
                val missing: Resource? = null
                println(missing.use { it == null })
                println(early())
                try {
                    Resource(IllegalStateException("close failure")).use { println("body") }
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
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "MainKt"])
            #expect(run.stdout == "true\nclose\n42\nbody\nclose\nclose failure\nclose\nprimary\nsuppressed\n")
        }
    }
}
#endif
