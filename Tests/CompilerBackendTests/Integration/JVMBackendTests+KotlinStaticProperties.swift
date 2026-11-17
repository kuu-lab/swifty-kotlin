#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinObjectPropertiesUseTheirStaticGetterSignatures() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            object Dispatchers {
                @JvmStatic val IO: String get() = "io"
                @JvmStatic @get:JvmName("readDefault") val Default: String? get() = null
                @JvmStatic fun getLookalike(): String = "method"
            }
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import api.Dispatchers
            fun main() {
                println(Dispatchers.IO)
                println(Dispatchers.Default ?: "fallback")
                println(Dispatchers.getLookalike())
            }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "io\nfallback\nmethod\n")

            let (_, rejected, errors) = try m22Build(
                root: root, sources: [("Missing.kt", "import api.Dispatchers\nfun invalid() = Dispatchers.lookalike")],
                name: "missing.jar", classpath: classpath
            )
            #expect(rejected != 0)
            #expect(errors.contains { $0.message.contains("Unresolved member function 'lookalike'") })
        }
    }
}
#endif
