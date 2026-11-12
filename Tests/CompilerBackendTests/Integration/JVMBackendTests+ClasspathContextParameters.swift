#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func classpathContextFunctionsReceiveLexicalContextValues() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            class Token(val value: String)
            context(token: Token)
            fun read(): String = token.value
            context(token: Token)
            fun String.appendToken(): String = this + token.value
            inline fun <A, R> inContext(value: A, action: context(A) () -> R): R = action(value)
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import api.Token
            import api.read
            import api.appendToken
            import api.inContext
            fun main() {
                val result = inContext(Token("outer")) {
                    println(read())
                    val nested = inContext(Token("inner")) { "seen ".appendToken() }
                    println(nested)
                    read()
                }
                println(result)
            }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "outer\nseen inner\nouter\n")

            let compose = try composeJVMFixture(root, stdlib: stdlib)
            let screen = """
            import androidx.compose.runtime.Composable
            import androidx.compose.runtime.currentComposer
            import api.Token
            import api.inContext
            import api.read
            import fixture.Bridge
            @Composable private fun Leaf(length: Int) { Bridge.record(currentComposer, length) }
            @Composable fun Root() {
                inContext(Token("context")) { Leaf(read().length) }
            }
            """
            let (composeApp, composeExit, composeDiagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", screen)], name: "screen.jar", classpath: [compose.path] + classpath
            )
            try #require(composeExit == 0, "\(composeDiagnostics.map(\.message))")
            let runner = """
            public final class ContextRunner {
                public static void main(String[] args) {
                    ScreenKt.Root(fixture.Bridge.COMPOSER, 0);
                    fixture.Bridge.checkClosed(3);
                }
            }
            """
            try runner.write(to: root.appendingPathComponent("ContextRunner.java"), atomically: true, encoding: .utf8)
            let runClasspath = ([composeApp.path, compose.path] + classpath).joined(separator: ":")
            let driver = try jvmTool("javac", ["-cp", runClasspath, "-d", ".", "ContextRunner.java"], root: root)
            try #require(driver.exitCode == 0, "\(driver.stderr)")
            let rendered = try java(["-Xverify:all", "-cp", root.path + ":" + runClasspath, "ContextRunner"])
            #expect(rendered.stdout == "7\n")
        }
    }
}
#endif
