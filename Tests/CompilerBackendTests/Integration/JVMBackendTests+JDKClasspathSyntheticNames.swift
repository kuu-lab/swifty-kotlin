#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func jdkClasspathSyntheticJavaNamesDoNotRedeclare(mode: EmitMode) throws {
        try withWorkspace { root in
            let sources: [(path: String, packageName: String, className: String)] = [
                ("jdk-src/java/io/BufferedReader.java", "java.io", "BufferedReader"),
                ("jdk-src/java/io/BufferedWriter.java", "java.io", "BufferedWriter"),
                ("jdk-src/java/util/concurrent/atomic/AtomicIntegerArray.java", "java.util.concurrent.atomic", "AtomicIntegerArray"),
                ("jdk-src/java/util/concurrent/atomic/AtomicLongArray.java", "java.util.concurrent.atomic", "AtomicLongArray"),
                ("jdk-src/java/math/BigDecimal.java", "java.math", "BigDecimal"),
                ("jdk-src/java/util/Locale.java", "java.util", "Locale"),
            ]
            for source in sources {
                let url = root.appendingPathComponent(source.path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "package \(source.packageName);\npublic class \(source.className) {}\n".write(to: url, atomically: true, encoding: .utf8)
            }
            _ = try jvmTool("javac", ["--release", "8", "-d", "jdk-classes"] + sources.map { $0.path }, root: root)
            _ = try jvmTool("jar", ["cf", "jdk.jar", "-C", "jdk-classes", "."], root: root)

            let result = try compile("fun main() = println(42)", root: root, mode: mode, classpath: [root.appendingPathComponent("jdk.jar").path])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.stdout == "42\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
