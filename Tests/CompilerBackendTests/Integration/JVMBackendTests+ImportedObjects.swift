#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinSingletonsKeepConstantsPropertiesAndIdentity() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture
            object Routes {
                const val home = "home"
                val Default: String = "default"
                fun path(value: String) = "$home/$value"
                fun isSame(other: Routes): Boolean = other === this
            }
            """.write(to: root.appendingPathComponent("Objects.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency.jar").path
            let compiled = try jvmTool("kotlinc", ["Objects.kt", "-d", dependency], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency, library.path]
            let source = """
            import fixture.Routes
            fun main() {
                println(Routes.home)
                println(Routes.Default)
                println(Routes.path("detail"))
                println(Routes.isSame(Routes))
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "home\ndefault\nhome/detail\ntrue\n")
        }
    }
}
#endif
