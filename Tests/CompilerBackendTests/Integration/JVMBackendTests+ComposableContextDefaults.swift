#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func composableDefaultAndBodyKeepNamedContextParameters() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root)
            let source = """
                import androidx.compose.runtime.Composable

                context(prefix: String)
                @Composable fun Screen(count: Int = prefix.length): String = prefix + count

                context(prefix: String)
                @Composable fun Root(): String = Screen()
                """
            let classpath = [runtime.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")

            try """
                import fixture.Bridge;
                public final class Driver {
                    public static void main(String[] args) {
                        System.out.println(ScreenKt.Root("prefix-", Bridge.COMPOSER, 0));
                    }
                }
                """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let runClasspath = ([app.path] + classpath).joined(separator: ":")
            let compiled = try jvmTool("javac", ["-cp", runClasspath, "-d", "driver", "Driver.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let driver = root.appendingPathComponent("driver").path
            let run = try java(["-cp", runClasspath + ":" + driver, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "prefix-7\n")
        }
    }
}
#endif
