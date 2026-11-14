#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmOverloadsConstructorsExposeDefaultMasksToJava() throws {
        try withWorkspace { root in
            let source = """
            package fixture
            class View @JvmOverloads constructor(
                val label: String = "default", val key: Int, val style: Int = key + 1
            ) {
                fun description(): String = "$label:$key:$style"
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("View.kt", source)], name: "app.jar")
            try #require(status == 0, "\(diagnostics.map(\.message))")
            try """
            import fixture.View;
            public class Inflate {
                public static void main(String[] args) throws Exception {
                    System.out.println(View.class.getConstructor(int.class).newInstance(4).description());
                    System.out.println(new View("explicit", 5).description());
                    System.out.println(new View("explicit", 5, 20).description());
                }
            }
            """.write(to: root.appendingPathComponent("Inflate.java"), atomically: true, encoding: .utf8)
            let compiler = try jvmTool("javac", ["-cp", app.path, "Inflate.java"], root: root)
            try #require(compiler.exitCode == 0, "\(compiler.stderr)")
            let run = try java(["-Xverify:all", "-cp", root.path + ":" + app.path, "Inflate"])
            #expect(run.stdout == "default:4:5\nexplicit:5:6\nexplicit:5:20\n")
        }
    }
}
#endif
