#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func importedNullableKotlinPropertyPreservesSafeCall() throws {
        try withWorkspace { root in
            let library = """
            package fixture
            class Message(val text: String)
            class Record(val message: Message?)
            fun record() = Record(null)
            """
            let (dependency, status, diagnostics) = try m22Build(root: root, sources: [("Data.kt", library)], name: "library.jar")
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let source = """
            import fixture.record
            fun main() {
                record().message?.let { println(it.text) }
                println("done")
            }
            """
            let (app, exit, appDiagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [dependency.path])
            try #require(exit == 0, "\(appDiagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + dependency.path, "MainKt"])
            #expect(run.stdout == "done\n")
        }
    }
}
#endif
