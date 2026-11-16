#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func overrideDiagnosticsOnlyCheckSourceDeclarations() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package views;
            public class ParentView {
                public int getDirection() { return 1; }
                public void setDirection(int direction) {}
            }
            """.write(to: root.appendingPathComponent("ParentView.java"), atomically: true, encoding: .utf8)
            try """
            package views
            @JvmInline value class Direction(val code: Int)
            class ChildView : ParentView() {
                val direction: Direction get() = Direction(4)
                fun label(): String = "child"
            }
            """.write(to: root.appendingPathComponent("ChildView.kt"), atomically: true, encoding: .utf8)
            let javac = try jvmTool("javac", ["--release", "8", "-d", "parent", "ParentView.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let parent = root.appendingPathComponent("parent").path
            let child = root.appendingPathComponent("child.jar").path
            let kotlinc = try jvmTool("kotlinc", ["ChildView.kt", "-classpath", parent, "-d", child], root: root)
            try #require(kotlinc.exitCode == 0, "\(kotlinc.stderr)")
            let classpath = [parent, child, library.path]
            let source = """
            import views.ChildView
            fun main() { println(ChildView().label()) }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "child\n")
            let invalid = """
            import views.ParentView
            class Invalid : ParentView() {
                override fun missing(): String = "no matching member"
            }
            """
            let (_, failure, errors) = try m22Build(
                root: root, sources: [("Bad.kt", invalid)], name: "bad.jar", classpath: classpath
            )
            #expect(failure != 0)
            #expect(errors.contains { $0.code == "KSWIFTK-SEMA-OVERRIDE-NOTHING" })
        }
    }
}
#endif
