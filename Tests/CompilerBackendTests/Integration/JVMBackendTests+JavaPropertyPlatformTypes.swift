#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaBeanPropertiesAllowPlatformNullAndFunctionOverrides() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public class Widget {
                private String title;
                public String getTitle() { return title; }
                public void setTitle(String value) { title = value; }
                public interface Checkable {
                    boolean isChecked();
                    void setChecked(boolean value);
                }
            }
            """.write(to: root.appendingPathComponent("Widget.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Widget.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Widget

            class Control : Widget.Checkable {
                private var isChecked = false
                override fun isChecked(): Boolean = isChecked
                override fun setChecked(value: Boolean) {
                    isChecked = value
                }
            }
            fun main() {
                val widget = Widget()
                widget.title = "visible"
                println(widget.title)
                widget.title = null
                println(widget.title == null)
                val control: Widget.Checkable = Control()
                control.setChecked(true)
                println(control.isChecked())
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classes]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "visible\ntrue\ntrue\n")
        }
    }
}
#endif
