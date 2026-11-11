#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// KUU-4524: an erased Java `Class<?>` return must be usable as the receiver
    /// of a Kotlin generic `Class<T>` extension.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4524JavaWildcardClassReceiverCompilesAndRuns(mode: EmitMode) throws {
        try withWorkspace { root in
            let classJava = root.appendingPathComponent("java/lang/Class.java")
            try FileManager.default.createDirectory(at: classJava.deletingLastPathComponent(), withIntermediateDirectories: true)
            try """
            package java.lang;
            public class Class<T> { }
            """.write(to: classJava, atomically: true, encoding: .utf8)

            let typesJava = root.appendingPathComponent("dep/Types.java")
            try FileManager.default.createDirectory(at: typesJava.deletingLastPathComponent(), withIntermediateDirectories: true)
            try """
            package dep;
            public final class Types {
                public static Class<?> type() { return Types.class; }
            }
            """.write(to: typesJava, atomically: true, encoding: .utf8)

            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "java/lang/Class.java", "dep/Types.java"], root: root)
            let dependency = root.appendingPathComponent("deps.jar")
            _ = try jvmTool("jar", ["cf", dependency.path, "-C", "deps", "."], root: root)

            let source = """
            import dep.Types
            fun <T> Class<T>.render(): String = "ok"
            fun main() { println(Types.type().render()) }
            """
            let classpath = mode == .jvmJar ? dependency.path : root.appendingPathComponent("deps").path
            let result = try compile(source, root: root, mode: mode, classpath: [classpath])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }

            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", output + ":" + classpath, "HelloKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "ok\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
