#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func unsignedArrayViewConversionsRunOnOfficialRuntime(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("unsignedArrayViewConversions.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("unsignedArrayViewConversions.out"), encoding: .utf8)
        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func unsignedArrayViewConversionRejectsNullPlatformReceiver(mode: EmitMode) throws {
        try withWorkspace { root in
            try """
            public class NullArrays {
                public static byte[] bytes() { return null; }
            }
            """.write(to: root.appendingPathComponent("NullArrays.java"), atomically: true, encoding: .utf8)
            let javaClasses = root.appendingPathComponent("java-classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", javaClasses, "NullArrays.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            fun main() {
                try {
                    NullArrays.bytes().asUByteArray()
                    println("no throw")
                } catch (e: NullPointerException) {
                    println("npe")
                }
            }
            """
            let runtime = try m11Runtime()
            let runtimePaths = runtime.split(separator: ":").map(String.init)
            let artifactName = mode == .jvmJar ? "app.jar" : "app-classes"
            let (artifact, exitCode, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: artifactName,
                mode: mode,
                classpath: [javaClasses] + runtimePaths
            )
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let classpath = artifact.path + ":" + javaClasses + ":" + runtime
            let generated = try java(["-Xverify:all", "-cp", classpath, "MainKt"])
            #expect(generated.exitCode == 0, "\(generated.stderr)")
            #expect(generated.stdout == "npe\n")
            let referenceBuild = try jvmTool("kotlinc", ["Main.kt", "-cp", javaClasses + ":" + runtime, "-d", "reference.jar"], root: root)
            try #require(referenceBuild.exitCode == 0, "\(referenceBuild.stderr)")
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + javaClasses + ":" + runtime, "MainKt"])
            #expect(reference.stdout == generated.stdout)
        }
    }
}
#endif
