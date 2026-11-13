#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func infersJavaGenericReturnFromCastTarget() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public class Views {
                public static class View {}
                public static class Label extends View {
                    public String text() { return "label"; }
                }
                public <T extends View> T find() { return (T) new Label(); }
                public <T extends View> T missing() { return null; }
            }
            """.write(to: root.appendingPathComponent("Views.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Views.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Views
            fun main() {
                val views = Views()
                val label = views.find() as Views.Label
                println(label.text())
                println(views.missing() as? Views.Label)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classes]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes + ":" + (try ownStdlibLibrary()).path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "label\nnull\n")

            let (_, failure, errors) = try m22Build(
                root: root, sources: [("Reject.kt", "import fixture.Views\nfun invalid() = Views().find() as String")],
                name: "reject.jar", classpath: [classes]
            )
            #expect(failure != 0)
            #expect(errors.contains { $0.severity == .error })
        }
    }
}
#endif
