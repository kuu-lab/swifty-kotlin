#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedCoroutineScopeReusesTheResidualNominal() throws {
        try withWorkspace { root in
            try """
            package kotlinx.coroutines;
            public interface CoroutineScope {
                String marker();
                static CoroutineScope sample() { return () -> "scope"; }
            }
            """.write(to: root.appendingPathComponent("CoroutineScope.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("deps")
            let compiled = try jvmTool("javac", ["--release", "8", "-d", dependency.path, "CoroutineScope.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import kotlinx.coroutines.CoroutineScope
            fun main() {
                val scope: CoroutineScope = CoroutineScope.sample()
                println(scope.marker())
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [dependency.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + dependency.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "scope\n")
        }
    }
}
#endif
