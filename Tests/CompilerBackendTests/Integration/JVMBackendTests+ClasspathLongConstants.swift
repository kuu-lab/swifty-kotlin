#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func importsMinimumLongConstant(mode: EmitMode) throws {
        try withWorkspace { root in
            let dependency = """
            package dep;
            public final class Limits {
                public static final long MIN = Long.MIN_VALUE;
                public static final long NEXT = Long.MIN_VALUE + 1;
            }
            """
            try dependency.write(to: root.appendingPathComponent("Limits.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Limits.java"], root: root)

            let source = """
            import dep.Limits

            const val minimum = Limits.MIN

            fun main() {
                println(minimum)
                println(Limits.MIN)
                println(Limits.NEXT)
            }
            """
            let classes = root.appendingPathComponent("deps").path
            let result = try compile(source, root: root, mode: mode, classpath: [classes])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let arguments = mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"]
            let execution = try java(arguments)
            #expect(execution.stdout == "-9223372036854775808\n-9223372036854775808\n-9223372036854775807\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
