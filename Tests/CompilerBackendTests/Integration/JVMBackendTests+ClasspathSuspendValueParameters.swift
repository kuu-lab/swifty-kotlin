#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedSuspendValueParameterKeepsKotlinOverload() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            @JvmInline
            value class Wait(val ticks: Long)
            fun wait(ticks: Long): Wait = Wait(ticks)
            suspend fun delay(value: Long): Long = value
            suspend fun delay(value: Wait): Long = value.ticks * 2
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.delay
            import fixture.wait
            suspend fun main() {
                println(delay(5L))
                println(delay(wait(5L)))
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "5\n10\n")
        }
    }
}
#endif
