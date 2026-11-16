#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importsJavaClassBoundsForPlatformOverrides() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public class Behavior<V extends Behavior.View> {
                public static class View {}
                public static class Widget extends View {}
                public boolean dependsOn(V child) { return false; }
                public static boolean dispatch(Behavior<Widget> behavior, Widget child) {
                    return behavior.dependsOn(child);
                }
            }
            """.write(to: root.appendingPathComponent("Behavior.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", dependency, "Behavior.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let classpath = [dependency]
            let source = """
            import fixture.Behavior

            class Candidate : Behavior<Behavior.Widget>() {
                override fun dependsOn(child: Behavior.Widget?): Boolean = child == null
            }

            fun main() {
                println(Behavior.dispatch(Candidate(), null))
                println(Behavior.dispatch(Candidate(), Behavior.Widget()))
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "true\nfalse\n")

            let rejected = """
            import fixture.Behavior
            fun invalid() = Behavior<String>()
            """
            let (_, failure, errors) = try m22Build(
                root: root, sources: [("Reject.kt", rejected)], name: "reject.jar", classpath: classpath
            )
            #expect(failure != 0)
            #expect(errors.contains { $0.severity == .error })
        }
    }
}
#endif
