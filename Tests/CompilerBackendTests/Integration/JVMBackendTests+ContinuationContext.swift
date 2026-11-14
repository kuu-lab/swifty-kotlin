#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmContinuationImplCapturesContextAtConstruction() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.coroutines.Continuation;
            import kotlin.coroutines.CoroutineContext;
            import kotlin.coroutines.EmptyCoroutineContext;
            import kotlin.coroutines.jvm.internal.ContinuationImpl;

            public final class Driver {
                private static final class Completion implements Continuation<Object> {
                    int reads;
                    boolean installed;
                    public CoroutineContext getContext() {
                        if (installed) throw new AssertionError("Completion context read after installation");
                        reads++;
                        return EmptyCoroutineContext.INSTANCE;
                    }
                    public void resumeWith(Object result) {}
                }

                private static final class Frame extends ContinuationImpl {
                    Frame(Continuation<Object> completion) { super(completion); }
                    Frame(Continuation<Object> completion, CoroutineContext context) { super(completion, context); }
                    @Override protected Object invokeSuspend(Object result) { return result; }
                }

                public static void main(String[] args) {
                    Completion completion = new Completion();
                    Frame first = new Frame(completion);
                    completion.installed = true;
                    System.out.println(first.getContext() == EmptyCoroutineContext.INSTANCE);
                    System.out.println(first.getContext() == EmptyCoroutineContext.INSTANCE);
                    System.out.println(completion.reads);
                    Frame explicit = new Frame(completion, EmptyCoroutineContext.INSTANCE);
                    System.out.println(explicit.getContext() == EmptyCoroutineContext.INSTANCE);
                    System.out.println(completion.reads);
                }
            }
            """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let official = try m11Runtime()
            let compiled = try jvmTool("javac", ["-cp", official, "Driver.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let expected = try java(["-Xverify:all", "-cp", root.path + ":" + official, "Driver"])
            let result = try java(["-Xverify:all", "-cp", root.path + ":" + library.path, "Driver"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "true\ntrue\n1\ntrue\n1\n")
            #expect(result.stdout == expected.stdout)
        }
    }

    /// Kotlin repro of the runtime bug: a real suspend function's generated
    /// ContinuationImpl must capture the completion's context at
    /// construction. Reading `continuation.context` after the completion
    /// stops serving `context` (post-installation re-entry) must not throw.
    @Test
    func kotlinSuspendContinuationCapturesContextAtConstruction() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.coroutines.*

            class Completion : Continuation<Any?> {
                var installed = false
                var reads = 0
                override val context: CoroutineContext
                    get() {
                        if (installed) throw AssertionError("context read after install")
                        reads++
                        return EmptyCoroutineContext
                    }
                override fun resumeWith(result: Result<Any?>) {}
            }

            fun main() {
                val block: suspend () -> Int = { 1 }
                val completion = Completion()
                val frame = block.createCoroutine(completion)
                completion.installed = true
                println(frame.context === EmptyCoroutineContext)
                println(frame.context === EmptyCoroutineContext)
                println(completion.reads)
            }
            """.write(to: root.appendingPathComponent("Probe.kt"), atomically: true, encoding: .utf8)
            let official = try m11Runtime()
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Probe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let expected = try java(["-Xverify:all", "-cp", app.path + ":" + official, "ProbeKt"])
            let result = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "ProbeKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == expected.stdout)
            #expect(result.stdout.contains("true"))
        }
    }
}
#endif
