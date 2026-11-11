#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaVarargSetterKeepsArrayGetterAvailable() throws {
        try withWorkspace { root in
            let source = """
                package dep;
                public class Widget {
                    private int[] values = new int[0];
                    public int[] getValues() { return values; }
                    public void setValues(int... values) { this.values = values; }
                    public static Child child() { return new Child(); }

                    public static class Child extends Widget {
                        @Override public int[] getValues() { return super.getValues(); }
                    }
                }
                """
            try source.write(to: root.appendingPathComponent("Widget.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Widget.java"], root: root)
            let dependencies = root.appendingPathComponent("deps").path
            let kotlin = """
                import dep.Widget

                fun main() {
                    val widget = Widget()
                    widget.setValues(41, 42)
                    println(widget.values[1])
                    val child = Widget.child()
                    child.setValues(43, 44)
                    println(child.values[0])
                }
                """
            let (exitCode, diagnostics) = try compile(kotlin, root: root, mode: .jvmClass, classpath: [dependencies])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let classes = root.appendingPathComponent("classes").path
            let result = try java(["-cp", "\(classes):\(dependencies)", "HelloKt"])
            #expect(result.stdout == "42\n43\n")

            let assignment = """
                import dep.Widget
                fun main() {
                    Widget().values = intArrayOf(1)
                    Widget.child().values = intArrayOf(2)
                }
                """
            let (assignmentExit, assignmentDiagnostics) = try compile(
                assignment, root: root, mode: .jvmClass, classpath: [dependencies]
            )
            #expect(assignmentExit == 1)
            #expect(assignmentDiagnostics.filter { $0.severity == .error }.map(\.code) == [
                "KSWIFTK-SEMA-0014", "KSWIFTK-SEMA-0014",
            ])
        }
    }
}
#endif
