#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedComposableMemberUsesDispatchReceiverAndActiveComposer() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root)
            // Keep the metadata emitted by the Kotlin Compose plugin for the lowered member signature.
            let dependency = #"""
            package fixture;
            import androidx.compose.runtime.Composable;
            import androidx.compose.runtime.Composer;

            @kotlin.Metadata(mv = {2, 0, 0}, k = 1, xi = 48,
                d1 = {"\000\030\n\002\030\002\n\002\020\000\n\000\n\002\020\016\n\002\b\004\n\002\020\b\n\000\b\007\030\0002\0020\001B\017\022\006\020\002\032\0020\003¢\006\004\b\004\020\005J\027\020\006\032\0020\0032\b\b\002\020\007\032\0020\bH\007¢\006\002\020\tR\016\020\002\032\0020\003X\004¢\006\002\n\000"},
                d2 = {"Lfixture/Provider;", "", "label", "", "<init>", "(Ljava/lang/String;)V",
                      "Render", "value", "", "(ILandroidx/compose/runtime/Composer;II)Ljava/lang/String;"})
            public final class Provider {
                private final String label;
                public Provider(String label) { this.label = label; }
                @Composable public final String Render(int value, Composer composer, int changed, int defaults) {
                    if (composer != Bridge.COMPOSER || changed != 0) throw new AssertionError("wrong composer");
                    composer.startReplaceableGroup(123);
                    String result = label + ((defaults & 1) != 0 ? 7 : value);
                    composer.endReplaceableGroup();
                    return result;
                }
            }
            """#
            try dependency.write(to: root.appendingPathComponent("Provider.java"), atomically: true, encoding: .utf8)
            let javac = try jvmTool("javac", ["--release", "8", "-cp", runtime.path + ":" + stdlib.path,
                                             "-d", "provider", "Provider.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let library = root.appendingPathComponent("provider")
            let consumer = """
            import androidx.compose.runtime.Composable
            import fixture.Provider

            @Composable fun Screen(provider: Provider): String =
                provider.Render() + "/" + provider.Render(value = 9)
            """
            let classpath = [library.path, runtime.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", consumer)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            try """
            import fixture.Bridge;
            import fixture.Provider;

            public final class Driver {
                public static void main(String[] args) {
                    System.out.println(ScreenKt.Screen(new Provider("row"), Bridge.COMPOSER, 0));
                    Bridge.checkClosed(5);
                }
            }
            """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let runClasspath = ([app.path] + classpath).joined(separator: ":")
            let compiled = try jvmTool("javac", ["-cp", runClasspath, "-d", "driver", "Driver.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", runClasspath + ":" + root.appendingPathComponent("driver").path, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "row7/row9\n")
        }
    }
}
#endif
