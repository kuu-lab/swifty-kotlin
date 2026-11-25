#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func qualifiedJavaSAMConstructorUsesTheNestedInterface() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public final class Owner {
                public interface Listener { void accept(String value); }
                public static void fire(Listener listener) { listener.accept("nested"); }
            }
            """.write(to: root.appendingPathComponent("Owner.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes")
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes.path, "Owner.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let main = """
            import fixture.Owner
            fun main() {
                val listener = Owner.Listener { value -> println(value) }
                Owner.fire(listener)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", main)], name: "app.jar", classpath: [classes.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes.path, "MainKt"])
            #expect(run.stdout == "nested\n")
        }
    }
}
#endif
