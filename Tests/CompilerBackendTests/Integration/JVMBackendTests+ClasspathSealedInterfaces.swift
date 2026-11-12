#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedSealedInterfaceWithNestedObjectSupportsExhaustiveWhen() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            sealed interface State {
                data object Offline : State
                data class Schedule(val label: String) : State
            }
            fun state(active: Boolean): State = if (active) State.Schedule("DroidKaigi") else State.Offline
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("deps")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", dependency.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency.path, own.path]
            let source = """
            import fixture.*
            fun render(state: State): String = when (state) {
                State.Offline -> "offline"
                is State.Schedule -> state.label
            }
            fun main() {
                println(render(state(false)))
                println(render(state(true)))
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "offline\nDroidKaigi\n")

            let incomplete = """
            import fixture.State
            fun render(state: State): String = when (state) {
                is State.Schedule -> state.label
            }
            """
            let (_, fullExit, fullErrors) = try m22Build(root: root, sources: [("Missing.kt", incomplete)], name: "missing.jar", classpath: classpath)
            #expect(fullExit == 1)
            #expect(fullErrors.filter { $0.severity == .error }.map(\.code) == ["KSWIFTK-SEMA-0071"])
            try FileManager.default.removeItem(at: dependency.appendingPathComponent("fixture/State$Offline.class"))
            let (_, partialExit, partialErrors) = try m22Build(root: root, sources: [("Missing.kt", incomplete)], name: "partial.jar", classpath: classpath)
            #expect(partialExit == 1)
            #expect(partialErrors.filter { $0.severity == .error }.map(\.code) == ["KSWIFTK-SEMA-0004"])
        }
    }
}
#endif
