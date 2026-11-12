#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaCovariantGetterKeepsInheritedMutableProperty() throws {
        try withWorkspace { root in
            let sources = [
                "Cell": """
                    public class Cell {
                        private Object text = "start";
                        public Object getText() { return text; }
                        public void setText(Object text) { this.text = text; }
                    }
                    """,
                "EditableCell": """
                    public class EditableCell extends Cell {
                        @Override public String getText() { return super.getText().toString(); }
                    }
                    """,
            ]
            for (name, source) in sources {
                try ("package dep;\n" + source).write(
                    to: root.appendingPathComponent(name + ".java"), atomically: true, encoding: .utf8
                )
            }
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Cell.java", "EditableCell.java"], root: root)
            let source = """
                import dep.EditableCell

                fun main() {
                    val cell = EditableCell()
                    cell.text = "next"
                    val refined: String = cell.getText()
                    println(refined)
                    println(cell.text.toString())
                }
                """
            let dependencies = root.appendingPathComponent("deps").path
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmClass, classpath: [dependencies])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let classes = root.appendingPathComponent("classes").path
            let result = try java(["-cp", "\(classes):\(dependencies)", "HelloKt"])
            #expect(result.stdout == "next\nnext\n")
        }
    }
}
#endif
