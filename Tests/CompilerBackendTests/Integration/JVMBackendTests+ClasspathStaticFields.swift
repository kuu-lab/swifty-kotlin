#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedJavaStaticFinalFieldsReadTheirRuntimeValues() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let platform = """
            package api;
            public class Platform {
                public static class Version {
                    public static final int CONSTANT = 7;
                    public static final int SDK_INT = Integer.parseInt("36");
                    public static final String LABEL = new String("Android");
                    private static final int SECRET = Integer.parseInt("42");
                }
            }
            """
            try platform.write(to: root.appendingPathComponent("Platform.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["--release", "8", "-d", "deps", "Platform.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [root.appendingPathComponent("deps").path, stdlib.path]
            let source = """
            import api.Platform
            fun main() {
                println(Platform.Version.CONSTANT)
                println(Platform.Version.SDK_INT)
                println(Platform.Version.LABEL)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "7\n36\nAndroid\n")
            let bytecode = try jvmTool("javap", ["-c", "-classpath", app.path, "MainKt"], root: root)
            #expect(bytecode.stdout.contains("Field api/Platform$Version.SDK_INT:I"))

            let (_, rejected, errors) = try m22Build(
                root: root, sources: [("Secret.kt", "import api.Platform\nfun secret() = Platform.Version.SECRET")],
                name: "secret.jar", classpath: classpath
            )
            #expect(rejected != 0)
            #expect(errors.contains { $0.message.contains("SECRET") })
        }
    }
}
#endif
