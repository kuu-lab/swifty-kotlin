#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedJavaExceptionIsAKotlinThrowable() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package api;
            public final class MissingActivity extends RuntimeException {
                public MissingActivity(String message) { super(message); }
            }
            """
            try provider.write(to: root.appendingPathComponent("MissingActivity.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-d", "dependency", "MissingActivity.java"], root: root)
            let classpath = [root.appendingPathComponent("dependency").path, stdlib.path]
            let source = """
            import api.MissingActivity

            fun main() {
                val base: Throwable = MissingActivity("missing")
                try {
                    throw base
                } catch (e: MissingActivity) {
                    println("caught")
                }
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "caught\n")

            let (_, rejected, errors) = try m22Build(
                root: root, sources: [("Bad.kt", "fun bad() { try {} catch (e: String) {} }")],
                name: "bad.jar", classpath: classpath
            )
            #expect(rejected != 0)
            #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0413" })
        }
    }
}
#endif
