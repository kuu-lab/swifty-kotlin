#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedExtensionsMatchTheExactFunctionCarrier() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package api
            interface Scope {
                fun String.align(action: (Int) -> Int): String
                fun String.align(value: Int): String
            }
            class TextScope : Scope {
                override fun String.align(action: (Int) -> Int): String = this + action(2)
                override fun String.align(value: Int): String = this + value
            }
            fun Scope.callback(): String = "x".align { it + 3 }
            fun Scope.scalar(): String = "y".align(4)
            """
            try provider.write(to: root.appendingPathComponent("Library.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Library.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import api.TextScope
            import api.callback
            import api.scalar
            fun main() {
                println(TextScope().callback())
                println(TextScope().scalar())
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "x5\ny4\n")
        }
    }
}
#endif
