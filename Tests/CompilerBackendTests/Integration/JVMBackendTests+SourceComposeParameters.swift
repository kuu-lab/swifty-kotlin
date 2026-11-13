#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func sourceComposeParametersKeepTheirJVMTypeAcrossLambdaCapture() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root, stdlib: stdlib)
            let classpath = [runtime.path, stdlib.path]
            let source = """
            import androidx.compose.runtime.Composable
            import androidx.compose.runtime.currentComposer
            import androidx.compose.ui.platform.ComposeView
            import fixture.Bridge

            @Composable fun invokeContent(content: @Composable () -> Unit) { content() }
            @Composable fun forward(content: @Composable () -> Unit) {
                ComposeView().setContent { invokeContent(content) }
            }
            @Composable fun screen() {
                val label = "rendered"
                forward {
                    println(label)
                    Bridge.depth(currentComposer)
                }
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            try """
            public final class Driver {
                public static void main(String[] args) {
                    ScreenKt.screen(fixture.Bridge.COMPOSER, 0);
                }
            }
            """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let cp = ([app.path] + classpath).joined(separator: ":")
            let driver = try jvmTool("javac", ["-cp", cp, "Driver.java"], root: root)
            try #require(driver.exitCode == 0, "\(driver.stderr)")
            let run = try java(["-Xverify:all", "-cp", cp + ":" + root.path, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "rendered\n")
        }
    }
}
#endif
