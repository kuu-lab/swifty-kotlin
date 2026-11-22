#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func boxedJavaBeanPropertiesPreserveNullAndPhysicalDescriptors() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public class Binding {
                private Integer itemCount;
                public Integer getItemCount() { return itemCount; }
                public void setItemCount(Integer value) { itemCount = value; }
                public void setItemCount(int value) { throw new AssertionError("wrong descriptor"); }
            }
            """.write(to: root.appendingPathComponent("Binding.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Binding.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Binding
            fun main() {
                val binding = Binding()
                val before: Int? = binding.itemCount
                println(before)
                binding.itemCount = 12
                val count: Int = binding.itemCount
                println(count)
                binding.itemCount = null
                println(binding.itemCount == null)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classes])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.stdout == "null\n12\ntrue\n")
        }
    }
}
#endif
