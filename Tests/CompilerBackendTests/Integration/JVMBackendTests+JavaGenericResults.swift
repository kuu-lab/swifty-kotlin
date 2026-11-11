#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaBoundedGenericResultUsesTheErasedMethodDescriptor() throws {
        try withWorkspace { root in
            let sources = [
                "View": "public class View {}",
                "Label": """
                    public class Label extends View {
                        public String title() { return "label"; }
                    }
                    """,
                "Lookup": """
                    public class Lookup {
                        @SuppressWarnings("unchecked")
                        public <T extends View> T find(int id) { return (T) new Label(); }
                    }
                    """,
            ]
            for (name, source) in sources {
                try ("package dep;\n" + source).write(
                    to: root.appendingPathComponent(name + ".java"), atomically: true, encoding: .utf8
                )
            }
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps"] + sources.keys.sorted().map { $0 + ".java" }, root: root)
            let dependencies = root.appendingPathComponent("deps").path
            let source = """
                import dep.Label
                import dep.Lookup

                fun main() {
                    val lookup = Lookup()
                    val explicit = lookup.find<Label>(1)
                    val inferred: Label = lookup.find(2)
                    println(explicit.title())
                    println(inferred.title())
                }
                """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmClass, classpath: [dependencies])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let classes = root.appendingPathComponent("classes").path
            let result = try java(["-cp", "\(classes):\(dependencies)", "HelloKt"])
            #expect(result.stdout == "label\nlabel\n")
        }
    }
}
#endif
