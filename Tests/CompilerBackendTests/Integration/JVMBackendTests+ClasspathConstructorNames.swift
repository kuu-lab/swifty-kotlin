#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinConstructorsKeepNamedArguments() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            sealed interface State {
                data class Countdown(val daysUntilStart: Int, val label: String) : State {
                    constructor(label: String) : this(0, label)
                }
            }
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.State
            fun main() {
                val countdown = State.Countdown(label = "DroidKaigi", daysUntilStart = 12)
                println(countdown.daysUntilStart)
                println(countdown.label)
                println(State.Countdown(label = "next").daysUntilStart)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "12\nDroidKaigi\n0\n")
        }
    }
}
#endif
