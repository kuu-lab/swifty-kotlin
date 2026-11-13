#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaSamOverloadPrefersNonGenericTaskForImplicitLambda() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture;
            import java.util.concurrent.Callable;

            public class Transaction {
                public void run(Runnable task) {
                    System.out.println("runnable");
                    task.run();
                }
                public <T> T run(Callable<T> task) throws Exception {
                    System.out.println("callable");
                    return task.call();
                }
            }
            """.write(to: root.appendingPathComponent("Transaction.java"), atomically: true, encoding: .utf8)
            let path = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", path, "Transaction.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let classpath = [path, stdlib.path]
            let source = """
            import fixture.Transaction
            import java.util.concurrent.Callable

            fun main() {
                val tx = Transaction()
                tx.run {
                    println("body")
                }
                println(tx.run(Callable { 42 }))
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "runnable\nbody\ncallable\n42\n")
        }
    }
}
#endif
