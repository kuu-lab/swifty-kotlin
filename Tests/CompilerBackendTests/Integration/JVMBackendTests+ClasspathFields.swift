#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func importsRuntimeStaticFields(mode: EmitMode) throws {
        try withWorkspace { root in
            let dependency = """
            package dep;
            public final class Build {
                public static final class VERSION {
                    public static final int SDK_INT = Integer.getInteger("dep.sdk", 37);
                    public static int counter = 41;
                }
            }
            """
            try dependency.write(to: root.appendingPathComponent("Build.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Build.java"], root: root)

            let source = """
            import dep.Build

            fun sdk(): Int = Build.VERSION.SDK_INT

            fun bump(): Int {
                Build.VERSION.counter += 1
                return Build.VERSION.counter
            }

            fun main() {
                println(sdk())
                println(bump())
                println(Build.VERSION.counter)
            }
            """
            let deps = root.appendingPathComponent("deps").path
            let result = try compile(source, root: root, mode: mode, classpath: [deps])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let output = mode == .jvmJar
                ? root.appendingPathComponent("hello.jar").path
                : root.appendingPathComponent("classes").path
            let execution = try java(["-cp", output + ":" + deps, "HelloKt"])
            #expect(execution.stdout == "37\n42\n42\n")
            #expect(execution.stderr.isEmpty)

            let inspection = try javap(["-c", "-classpath", output + ":" + deps, "HelloKt"])
            #expect(inspection.exitCode == 0, "\(inspection.stderr)")
            #expect(inspection.stdout.contains("getstatic"))
            #expect(inspection.stdout.contains("dep/Build$VERSION.SDK_INT:I"))
            #expect(inspection.stdout.contains("putstatic"))
            #expect(inspection.stdout.contains("dep/Build$VERSION.counter:I"))
        }
    }
}
#endif
