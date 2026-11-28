#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedComposableMemberPassesMultipleDefaultMasks() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root, stdlib: stdlib)
            let fixtureDirectory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/ImportedComposeMultiDefaultMasks", isDirectory: true)
            let panelClass = try Data(contentsOf: fixtureDirectory.appendingPathComponent("Panel.class"))
            let provider = root.appendingPathComponent("provider/fixture")
            try FileManager.default.createDirectory(at: provider, withIntermediateDirectories: true)
            try panelClass.write(to: provider.appendingPathComponent("Panel.class"))
            try """
                package androidx.compose.runtime;
                public final class ComposerKt {
                    public static boolean isTraceInProgress() { return false; }
                    public static void traceEventStart(int key, int changed0, int changed1, String info) {}
                    public static void traceEventEnd() {}
                }
                """.write(to: root.appendingPathComponent("ComposerKt.java"), atomically: true, encoding: .utf8)
            try """
                package kotlin.jvm.internal;
                public final class Intrinsics {
                    public static void checkNotNullParameter(Object value, String name) {
                        if (value == null) throw new NullPointerException(name);
                    }
                }
                """.write(to: root.appendingPathComponent("Intrinsics.java"), atomically: true, encoding: .utf8)
            let runtimePatch = try jvmTool(
                "javac", ["--release", "8", "-d", "provider", "ComposerKt.java", "Intrinsics.java"], root: root
            )
            try #require(runtimePatch.exitCode == 0, "\(runtimePatch.stderr)")

            let consumer = """
                import androidx.compose.runtime.Composable
                import fixture.Panel

                @Composable fun Screen(panel: Panel) {
                    println(panel.render(
                        p1 = 1, p2 = 2, p3 = 3, p4 = 4, p5 = 5, p6 = 6, p7 = 7, p8 = 8, p9 = 9,
                        p10 = 10, p11 = 11, p12 = 12, p13 = 13, p14 = 14, p15 = 15, p16 = 16, p17 = 17,
                        p18 = 18, p19 = 19, p20 = 20, p21 = 21, p22 = 22, p23 = 23, p24 = 24, p25 = 25,
                        p26 = 26, p27 = 27, p28 = 28, p29 = 29, p30 = 30
                    ) { println("callback") })
                }
                """
            let classpath = [root.appendingPathComponent("provider").path, runtime.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", consumer)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")

            try """
                import fixture.Bridge;
                import fixture.Panel;
                public final class Driver {
                    public static void main(String[] args) {
                        ScreenKt.Screen(new Panel(), Bridge.COMPOSER, 0);
                    }
                }
                """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let runClasspath = ([app.path] + classpath).joined(separator: ":")
            let compiled = try jvmTool("javac", ["-cp", runClasspath, "-d", "driver", "Driver.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let driver = root.appendingPathComponent("driver").path
            let run = try java(["-cp", runClasspath + ":" + driver, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "callback\n38\n")
        }
    }
}
#endif
