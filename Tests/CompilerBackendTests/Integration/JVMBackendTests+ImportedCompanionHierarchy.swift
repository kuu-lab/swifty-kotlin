#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedCompanionsKeepSuperclassAndNestedClass() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture
            open class Base { fun inherited(value: Int): Int = value + 1 }
            class Logger {
                companion object : Base() {
                    class Factory { fun label(): String = "nested" }
                }
            }
            """.write(to: root.appendingPathComponent("Companions.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency.jar").path
            let compiled = try jvmTool("kotlinc", ["Companions.kt", "-d", dependency], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency, library.path]
            let source = """
            import fixture.Logger
            import fixture.Logger.Companion.Factory
            fun main() {
                println(Logger.inherited(6))
                println(Factory().label())
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "7\nnested\n")
        }
    }
}
#endif
