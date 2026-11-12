#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedFinalKotlinMethodKeepsNamedArguments() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            enum class Day {
                Today;
                fun at(hour: Int, minute: Int): Int = hour * 60 + minute
            }
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.Day
            fun main() { println(Day.Today.at(minute = 12, hour = 2)) }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "132\n")
        }
    }
}
#endif
