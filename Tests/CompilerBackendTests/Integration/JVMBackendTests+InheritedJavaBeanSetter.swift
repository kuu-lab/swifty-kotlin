#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func inheritedBeanSetterUsesThePublicOverrideOwner() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public class Base<T> {
                private T value;
                public T getValue() { return value; }
                protected void setValue(T next) { value = next; }
            }
            """.write(to: root.appendingPathComponent("Base.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            public class Mutable<T> extends Base<T> {
                @Override public void setValue(T next) { super.setValue(next); }
            }
            """.write(to: root.appendingPathComponent("Mutable.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Base.java", "Mutable.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Mutable
            fun main() {
                val mutable = Mutable<String>()
                mutable.value = "outside"
                println(mutable.value)
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classes])
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.stdout == "outside\n")
        }
    }
}
#endif
