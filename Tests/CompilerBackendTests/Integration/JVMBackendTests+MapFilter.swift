#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func mapFilterPreservesIterationOrderAndTheInputMap() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val items = linkedMapOf("one" to 1, "two" to 2, "three" to 3)
                println(items.filter { it.value % 2 != 0 }.keys.joinToString())
                println(items.filter { entry -> entry.key == "absent" }.isEmpty())
                println(items.toList().map { it.first }.joinToString())
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "one, three\ntrue\none, two, three\n")
        }
    }
}
#endif
