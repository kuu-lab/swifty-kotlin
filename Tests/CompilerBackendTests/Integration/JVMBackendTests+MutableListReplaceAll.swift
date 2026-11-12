#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableListReplaceAllMatchesKotlinAndJavaConsumers(mode: EmitMode) throws {
        let library = try ownStdlibRuntime()
        try withWorkspace { root in
            let result = try compile("""
            fun newNumbers(): MutableList<Int> = mutableListOf(1, 2, 3)

            fun incrementNumbers(values: MutableList<Int>) {
                values.replaceAll { it + 1 }
            }

            fun main() {
                val values = mutableListOf(1, 2, 3)
                values.replaceAll { it + 1 }
                println(values)

                val calls = mutableListOf<Int>()
                val ordered = mutableListOf(3, 1, 2)
                ordered.replaceAll {
                    calls.add(it)
                    it * 10
                }
                println(calls)
                println(ordered)

                val empty = mutableListOf<Int>()
                var visited = 0
                empty.replaceAll {
                    visited += 1
                    it + 1
                }
                println("empty=$empty visited=$visited")

                ordered.add(1, 15)
                ordered[0] = 31
                println(ordered.removeAt(1))
                println(ordered)
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            let expected = """
            [2, 3, 4]
            [3, 1, 2]
            [30, 10, 20]
            empty=[] visited=0
            15
            [31, 10, 20]
            """ + "\n"
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)

            let javaConsumer = root.appendingPathComponent("MutableListReplaceAllJavaConsumer.java")
            try """
            import java.util.List;

            public final class MutableListReplaceAllJavaConsumer {
                public static void main(String[] args) {
                    List<Integer> values = HelloKt.newNumbers();
                    HelloKt.incrementNumbers(values);
                    values.replaceAll(value -> value * 2);
                    System.out.println(values);
                }
            }
            """.write(to: javaConsumer, atomically: true, encoding: .utf8)
            let javaClasspath = artifact + ":" + library.path
            let javaCompile = try javac(["-cp", javaClasspath, "-d", root.path, javaConsumer.path])
            try #require(javaCompile.exitCode == 0, "\(javaCompile.stderr)")
            let javaExecution = try java(["-cp", javaClasspath + ":" + root.path, "MutableListReplaceAllJavaConsumer"])
            #expect(javaExecution.stdout == "[4, 6, 8]\n")
            #expect(javaExecution.stderr.isEmpty)

            let referenceCompile = try jvmTool("kotlinc", ["hello.kt", "-d", "reference.jar"], root: root)
            try #require(referenceCompile.exitCode == 0, "\(referenceCompile.stderr)")
            let runtime = try m11Runtime()
            let referenceArtifact = root.appendingPathComponent("reference.jar").path
            let referenceExecution = try java(["-cp", referenceArtifact + ":" + runtime, "HelloKt"])
            #expect(referenceExecution.stdout == expected)
            #expect(referenceExecution.stderr.isEmpty)

            let referenceJavaClasspath = referenceArtifact + ":" + runtime
            let referenceJavaCompile = try javac(["-cp", referenceJavaClasspath, "-d", root.path, javaConsumer.path])
            try #require(referenceJavaCompile.exitCode == 0, "\(referenceJavaCompile.stderr)")
            let referenceJavaExecution = try java(["-cp", referenceJavaClasspath + ":" + root.path, "MutableListReplaceAllJavaConsumer"])
            #expect(referenceJavaExecution.stdout == "[4, 6, 8]\n")
            #expect(referenceJavaExecution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableListReplaceAllRejectsReadOnlyList(mode: EmitMode) throws {
        let library = try ownStdlibRuntime()
        try withWorkspace { root in
            let source = """
            fun main() {
                val values: List<Int> = listOf(1, 2, 3)
                values.replaceAll { it + 1 }
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0024" })
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }
}
#endif
