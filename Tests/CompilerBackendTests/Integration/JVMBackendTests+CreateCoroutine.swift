#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func createCoroutineDefersInvocationAndCanOnlyResumeOnce() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
                import kotlin.coroutines.*

                fun main() {
                    val completion = object : Continuation<String> {
                        override val context: CoroutineContext get() = EmptyCoroutineContext
                        override fun resumeWith(result: Result<String>) {
                            println(result.getOrThrow())
                        }
                    }
                    val scoped: suspend String.() -> String = { this + "!" }
                    val coroutine = scoped.createCoroutine("receiver", completion)
                    println("created")
                    coroutine.resume(Unit)
                    try {
                        coroutine.resume(Unit)
                        println("resumed twice")
                    } catch (failure: IllegalStateException) {
                        println("already resumed")
                    }
                    val plain: suspend () -> String = { "plain" }
                    plain.createCoroutine(completion).resume(Unit)
                }
                """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            _ = try jvmTool("kotlinc", ["Main.kt", "-d", "precompiled.jar"], root: root)
            for consumer in [app, root.appendingPathComponent("precompiled.jar")] {
                let run = try java(["-Xverify:all", "-cp", consumer.path + ":" + stdlib.path, "MainKt"])
                #expect(run.stdout == "created\nreceiver!\nalready resumed\nplain\n")
                #expect(run.stderr.isEmpty)
            }
        }
    }
}
#endif
