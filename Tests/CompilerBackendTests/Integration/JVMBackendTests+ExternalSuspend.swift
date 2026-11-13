#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    private func externalSuspendProvider(_ root: URL) throws -> URL {
        try """
        @file:JvmName("SuspendApi")
        package fixture

        import kotlin.coroutines.Continuation
        import kotlin.coroutines.resume
        import kotlin.coroutines.suspendCoroutine

        suspend fun fast(n: Int): Int = n + 1

        @JvmName("fastText")
        suspend fun fast(n: String): String = n + "!"

        suspend fun nullable(n: Int?): Int? = n
        suspend fun pause(gate: Gate): Int = gate.await()

        fun explicit(n: Int, continuation: Continuation<Int>): Any? = n + 3

        class Gate {
            private var pending: Continuation<Int>? = null

            suspend fun getLabel(): String = "ready"
            suspend fun await(): Int = suspendCoroutine { pending = it }

            fun release(value: Int) {
                val continuation = pending!!
                pending = null
                continuation.resume(value)
            }
        }
        """.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["Provider.kt", "-d", "provider.jar"], root: root)
        return root.appendingPathComponent("provider.jar")
    }

    @Test
    func externalKotlinSuspendCallsMatchKotlinc() throws {
        try withWorkspace { root in
            let provider = try externalSuspendProvider(root)
            let runtime = try m11Runtime()
            try """
            package fixture;
            import kotlin.coroutines.Continuation;

            public final class JavaPeer {
                public static int twice(int n) { return n * 2; }
                public static Object explicit(int n, Continuation<? super Integer> continuation) { return n + 4; }
            }
            """.write(to: root.appendingPathComponent("JavaPeer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-cp", runtime, "-d", "java", "JavaPeer.java"], root: root)
            _ = try jvmTool("jar", ["uf", provider.path, "-C", "java", "fixture"], root: root)

            let compiled = try compile("""
            import fixture.*
            import kotlin.coroutines.*

            class IntSink : Continuation<Int> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Int>) { error("unexpected resume") }
            }

            class Done : Continuation<Unit> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Unit>) {
                    result.getOrThrow()
                    println("done")
                }
            }

            fun main() {
                val sink = IntSink()
                println(explicit(5, sink))
                println(JavaPeer.explicit(5, sink))
                println(JavaPeer.twice(5))

                val gate = Gate()
                val work: suspend () -> Unit = {
                    val first = fast(n = 40)
                    println(first)
                    println(fast("ok"))
                    println(nullable(null))
                    println(nullable(7) ?: -1)
                    println(gate.getLabel())
                    val second = pause(gate)
                    println(first + second)
                    val third = gate.await()
                    println(first + second + third)
                }
                work.startCoroutine(Done())
                println("paused top-level")
                gate.release(1)
                println("paused member")
                gate.release(2)
            }
            """, root: root, mode: .jvmJar, classpath: [provider.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", provider.path, "-d", "reference.jar"], root: root)
            let dependencies = ":" + provider.path + ":" + runtime
            let generated = try java(["-cp", root.appendingPathComponent("hello.jar").path + dependencies, "HelloKt"])
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + dependencies, "HelloKt"])
            #expect(generated.stderr.isEmpty)
            #expect(generated.stdout == reference.stdout)
            #expect(reference.stdout == "8\n9\n10\n41\nok!\nnull\n7\nready\npaused top-level\n42\npaused member\n44\ndone\n")
        }
    }

    @Test
    func externalKotlinSuspendFunctionTypesResolveAndRun() throws {
        try withWorkspace { root in
            try """
            package fixture

            class Widget

            suspend fun Widget.render(content: (Int, Int) -> Unit) {
                content(20, 22)
            }
            """.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Provider.kt", "-d", "provider.jar"], root: root)
            let provider = root.appendingPathComponent("provider.jar")

            let compiled = try compile("""
            import fixture.Widget
            import fixture.render
            import kotlin.coroutines.*

            class Done : Continuation<Unit> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Unit>) {
                    result.getOrThrow()
                    println("done")
                }
            }

            fun main() {
                val work: suspend () -> Unit = {
                    Widget().render { left, right -> println(left + right) }
                }
                work.startCoroutine(Done())
            }
            """, root: root, mode: .jvmJar, classpath: [provider.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let runtime = try m11Runtime()
            let execution = try java([
                "-cp", root.appendingPathComponent("hello.jar").path + ":" + provider.path + ":" + runtime,
                "HelloKt",
            ])
            #expect(execution.stderr.isEmpty)
            #expect(execution.stdout == "42\ndone\n")
        }
    }

    @Test
    func externalKotlinSuspendRequiresSuspendContext() throws {
        try withWorkspace { root in
            let provider = try externalSuspendProvider(root)
            let compiled = try compile("""
            import fixture.Gate
            import fixture.fast

            fun main() {
                println(fast(40))
                println(Gate().getLabel())
            }
            """, root: root, mode: .jvmJar, classpath: [provider.path])
            #expect(compiled.0 == 1)
            let codes = compiled.1.filter { $0.severity == .error }.map(\.code)
            #expect(codes == ["KSWIFTK-SEMA-0308", "KSWIFTK-SEMA-0308"])
        }
    }
}
#endif
