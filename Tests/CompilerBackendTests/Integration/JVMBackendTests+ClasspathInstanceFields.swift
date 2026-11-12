#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedJavaInstanceFieldsReadAndWriteThroughJvmFields() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture;

            public class Metrics extends BaseMetrics {
                public float density = 2.0f;
                public final int width = 8;
                private int hidden = 99;
                public float getDensity() { return 99.0f; }
            }
            """
            try provider.write(to: root.appendingPathComponent("Metrics.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            public class BaseMetrics {
                public float getDensity() { return 100.0f; }
            }
            """.write(to: root.appendingPathComponent("BaseMetrics.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("deps")
            let compiled = try jvmTool("javac", ["--release", "8", "-d", dependency.path, "BaseMetrics.java", "Metrics.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency.path, own.path]
            let source = """
            import fixture.Metrics
            fun main() {
                val metrics = Metrics()
                println(metrics.density)
                metrics.density += 0.5f
                println(metrics.density)
                println(metrics.getDensity())
                println(metrics.width)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "2.0\n2.5\n99.0\n8\n")
            let rejected = """
            import fixture.Metrics
            fun reject(metrics: Metrics) { metrics.width = 10 }
            """
            let (_, rejectExit, _) = try m22Build(root: root, sources: [("Reject.kt", rejected)], name: "reject.jar", classpath: classpath)
            #expect(rejectExit == 1)
        }
    }
}
#endif
