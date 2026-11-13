#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmInlineGenericResultBoxesUnit() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun record() { println("recorded") }

            fun main() {
                val result: Result<Unit> = runCatching { record() }
                println(result.getOrThrow() == Unit)
                println(runCatching { 42 }.getOrThrow())
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [library.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "recorded\ntrue\n42\n")
        }
    }
}
#endif
