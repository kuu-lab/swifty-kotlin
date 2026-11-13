#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedCompositionLocalCurrentPreservesReadOnlyContract() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root)
            let source = """
            import androidx.compose.runtime.Composable
            import androidx.compose.runtime.CompositionLocal
            import androidx.compose.runtime.ReadOnlyComposable

            @Composable @ReadOnlyComposable
            fun readValue(local: CompositionLocal<String>): String = local.current
            """
            for readOnly in [true, false] {
                let annotation = readOnly ? "@ReadOnlyComposable" : ""
                let provider = """
                package androidx.compose.runtime;

                public class CompositionLocal<T> {
                    private final T value;
                    public CompositionLocal(T value) { this.value = value; }
                    @Composable \(annotation)
                    public T getCurrent(Composer composer, int changes) {
                        if (composer != fixture.Bridge.COMPOSER || changes != 0) throw new AssertionError();
                        return value;
                    }
                }
                """
                try provider.write(to: root.appendingPathComponent("CompositionLocal.java"), atomically: true, encoding: .utf8)
                let directory = readOnly ? "readonly" : "ordinary"
                _ = try jvmTool("javac", ["-cp", runtime.path, "-d", directory, "CompositionLocal.java"], root: root)
                let classpath = [root.appendingPathComponent(directory).path, runtime.path, stdlib.path]
                let (app, exit, diagnostics) = try m22Build(
                    root: root, sources: [("Screen.kt", source)], name: "\(directory).jar", classpath: classpath
                )
                if !readOnly {
                    #expect(exit != 0)
                    #expect(diagnostics.contains { $0.message.contains("that are not '@ReadOnlyComposable'") })
                    continue
                }
                try #require(exit == 0, "\(diagnostics.map(\.message))")
                let driver = """
                import androidx.compose.runtime.CompositionLocal;
                import fixture.Bridge;

                public class Driver {
                    public static void main(String[] args) {
                        System.out.println(ScreenKt.readValue(new CompositionLocal<>("session"), Bridge.COMPOSER, 0));
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
                #expect(run.stdout == "session\n")
            }
        }
    }
}
#endif
