#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func jvmInlineCallbackCanCallTheSameInlineFunctionAgain() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                println("outer".also { outer ->
                    "inner".also { println("$outer/$it") }
                })
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [library.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "outer/inner\nouter\n")
        }
    }
}
#endif
