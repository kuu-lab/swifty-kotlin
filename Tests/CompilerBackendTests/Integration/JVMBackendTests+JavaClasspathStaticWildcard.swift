#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaClasspathStaticMethodsAreAvailableInStarImports() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public class Tools {
                public static <T> T same(T value) { return value; }
            }
            """.write(to: root.appendingPathComponent("Tools.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Tools.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                import fixture.Tools.*
                fun main() {
                    val copied: String = same("ok")
                    println(copied)
                }
                """)],
                name: "app.jar", classpath: [classes]
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "ok\n")
        }
    }
}
#endif
