#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaGenericBeanAccessorsKeepTheSharedTypeParameter() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public class Box<T> {
                private T value;
                public T getValue() { return value; }
                public void setValue(T value) { this.value = value; }
            }
            """.write(to: root.appendingPathComponent("Box.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Box.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Box
            class TextBox : Box<String>()
            fun main() {
                val box = TextBox()
                box.value = "typed"
                val value: String? = box.value
                println(value)
                box.value = null
                println(box.value == null)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classes]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "typed\ntrue\n")
        }
    }
}
#endif
