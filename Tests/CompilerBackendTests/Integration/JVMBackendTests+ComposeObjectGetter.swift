#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmComposeObjectPropertyIsAValueBesideItsSameNamedFunction() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root)
            let source = """
            import androidx.compose.runtime.Composable
            import androidx.compose.runtime.ReadOnlyComposable

            object Theme {
                val colors: String get() = "colors"
            }

            @Composable fun Theme() {}

            @Composable @ReadOnlyComposable
            fun currentColors(): String = Theme.colors
            """
            let classpath = [runtime.path, own.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let driver = """
            import fixture.Bridge;

            public class Driver {
                public static void main(String[] args) {
                    System.out.println(ScreenKt.currentColors(Bridge.COMPOSER, 0));
                    Bridge.checkClosed(0);
                }
            }
            """
            try driver.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let appClasspath = ([app.path] + classpath).joined(separator: ":")
            _ = try jvmTool("javac", ["-cp", appClasspath, "-d", "driver", "Driver.java"], root: root)
            let driverPath = root.appendingPathComponent("driver").path
            let run = try java(["-Xverify:all", "-cp", appClasspath + ":" + driverPath, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "colors\n")
        }
    }
}
#endif
