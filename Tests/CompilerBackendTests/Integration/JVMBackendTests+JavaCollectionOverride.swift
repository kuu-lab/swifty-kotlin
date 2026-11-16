#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaCollectionParameterAcceptsMutableOverride() throws {
        try withWorkspace { root in
            try """
            package fixture;
            import java.util.List;
            public abstract class Listener {
                public abstract void update(List<String> values);
                public static void fire(Listener listener, List<String> values) { listener.update(values); }
            }
            """.write(to: root.appendingPathComponent("Listener.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Listener.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Listener
            class MutableListener : Listener() {
                override fun update(values: MutableList<String>) { values.add("callback") }
            }
            fun main() {
                val values = java.util.ArrayList<String>()
                values.add("first")
                Listener.fire(MutableListener(), values)
                println(values.size)
                println(values[1])
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classes])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "2\ncallback\n")

            let rejected = """
            import fixture.Listener
            class Wrong : Listener() {
                override fun update(values: MutableList<Int>) {}
            }
            """
            let (_, status, errors) = try m22Build(root: root, sources: [("Wrong.kt", rejected)], name: "wrong.jar", classpath: [classes])
            #expect(status != 0)
            #expect(errors.contains { $0.code == "KSWIFTK-SEMA-OVERRIDE-NOTHING" })
        }
    }
}
#endif
