#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaArrayEntriesCanBeNullWhenPassedBackToJava() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public class Drawables {
                public String[] getSlots() { return new String[] { "left", null }; }
                public void replace(String left, String right) {
                    System.out.println(left + ":" + right);
                }
            }
            """.write(to: root.appendingPathComponent("Drawables.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Drawables.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Drawables
            fun main() {
                val drawables = Drawables()
                val slots = drawables.slots
                drawables.replace(slots[0], slots[1])
                val method = drawables.getSlots()
                println(method[1] == null)
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classes])
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.stdout == "left:null\ntrue\n")
        }
    }
}
#endif
