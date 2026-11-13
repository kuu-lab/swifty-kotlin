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
}
#endif
