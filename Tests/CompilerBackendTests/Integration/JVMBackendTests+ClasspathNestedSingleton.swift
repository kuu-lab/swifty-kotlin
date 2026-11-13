#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedNestedSingletonWithExternalSealedSibling() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            sealed interface SizeMode {
                data object Exact : SizeMode
                data class Responsive(val width: Int) : SizeMode
            }
            class Outside { class Preview : SizeMode }
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.SizeMode
            class Widget { val sizeMode: SizeMode = SizeMode.Exact }
            fun main() {
                println(Widget().sizeMode === fixture.SizeMode.Exact)
                println(SizeMode.Responsive(24).width)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "true\n24\n")
        }
    }
}
#endif
