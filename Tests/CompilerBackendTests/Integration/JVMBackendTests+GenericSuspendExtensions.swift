#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedGenericSuspendExtensionsPreserveReceiverAndResultTypes() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture

            class Box<T>(val value: T)
            fun strings(): Box<String> = Box("value")
            fun numbers(): Box<Long> = Box(41L)
            suspend fun <T> Box<T>.read(): T = value
            suspend fun <T> Box<T>.missing(): T? = null
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import fixture.*
            import kotlin.coroutines.*

            class Done : Continuation<Unit> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Unit>) { result.getOrThrow() }
            }

            fun main() {
                val work: suspend () -> Unit = {
                    val text: String = strings().read()
                    println(text.length)
                    println(numbers().read() + 1L)
                    println(strings().missing() ?: "missing")
                }
                work.startCoroutine(Done())
            }
            """
            let classpath = [library.path, own.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "5\n42\nmissing\n")
        }
    }
}
#endif
