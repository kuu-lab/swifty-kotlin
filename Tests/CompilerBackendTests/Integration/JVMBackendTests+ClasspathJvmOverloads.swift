#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func generatedJvmOverloadDoesNotShadowDeclaredMember() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            class Tracer {
                fun instant(name: String): String = name
                @JvmOverloads
                fun instant(name: String, callback: (String) -> Unit = {}) { callback(name) }
                @JvmOverloads
                fun other(name: String, suffix: String = "!"): String = name + suffix
            }
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.Tracer
            fun main() {
                val tracer = Tracer()
                println(tracer.instant("declared"))
                tracer.instant("callback") { println(it) }
                println(tracer.other("retained"))
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "declared\ncallback\nretained!\n")
        }
    }
}
#endif
