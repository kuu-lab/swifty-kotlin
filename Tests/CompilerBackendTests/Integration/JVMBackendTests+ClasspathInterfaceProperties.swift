#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedInterfacePropertiesKeepGenericGetterTypes() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package kotlinx.coroutines.flow
            interface Flow<out T>
            interface StateFlow<out T> : Flow<T>
            interface Clock { val offset: StateFlow<String> }
            class CurrentState : StateFlow<String>
            fun clock(): Clock = object : Clock { override val offset = CurrentState() }
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import kotlinx.coroutines.flow.Clock
            import kotlinx.coroutines.flow.Flow
            import kotlinx.coroutines.flow.clock
            fun offset(clock: Clock): Flow<String> = clock.offset
            fun main() { println(offset(clock()).javaClass.simpleName) }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "CurrentState\n")
        }
    }
}
#endif
