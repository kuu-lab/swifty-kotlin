#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func iterableAndSequenceRunningFoldMatchKotlinc() throws {
        let source = #"""
        fun iterableRunningFold(values: Iterable<Int>): List<Int> =
            values.runningFold(0) { acc, value -> acc + value }

        fun sequenceRunningFold(values: Iterable<Int>): List<Int> =
            values.asSequence().runningFold(0) { acc, value -> acc + value }.toList()

        fun main() {
            println(listOf(1, 2, 3).runningFold(0) { acc, value -> acc + value })
            println(sequenceOf(1, 2, 3).runningFold(0) { acc, value -> acc + value }.toList())
            println(emptyList<Int>().runningFold(7) { acc, value -> acc + value })
            println(emptySequence<Int>().runningFold(9) { acc, value -> acc + value }.toList())
            println(listOf(1, 2, 3).runningFold("seed") { acc, value -> acc + value })
            var operations = 0
            val lazy = sequenceOf(1, 2, 3).runningFold(0) { acc, value ->
                operations += 1
                acc + value
            }
            println(operations)
            println(lazy.first())
            println(operations)
            println(lazy.toList())
            println(operations)
        }
        """#
        let expected = "[0, 1, 3, 6]\n[0, 1, 3, 6]\n[7]\n[9]\n[seed, seed1, seed12, seed123]\n0\n0\n0\n[0, 1, 3, 6]\n3\n"

        try withWorkspace { root in
            let app = try m22Build(root: root, sources: [("RunningFold.kt", source)], name: "running-fold.jar")
            try #require(app.1 == 0, "KSwiftK diagnostics: \(app.2.map(\.message))")

            let runtime = try m11Runtime()
            let candidate = try java(["-cp", app.0.path + ":" + runtime, "RunningFoldKt"])
            #expect(candidate.exitCode == 0, "KSwiftK stderr: \(candidate.stderr)")
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["-no-reflect", "-classpath", runtime, "RunningFold.kt", "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "RunningFoldKt"])
            #expect(reference.exitCode == 0, "kotlinc stderr: \(reference.stderr)")
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
            #expect(candidate.stdout == reference.stdout)

            let javaConsumer = #"""
            import java.util.Arrays;
            import java.util.List;

            public final class RunningFoldJavaConsumer {
                public static void main(String[] args) {
                    List<Integer> values = Arrays.asList(1, 2, 3);
                    System.out.println(RunningFoldKt.iterableRunningFold(values));
                    System.out.println(RunningFoldKt.sequenceRunningFold(values));
                }
            }
            """#
            try javaConsumer.write(to: root.appendingPathComponent("RunningFoldJavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-cp", app.0.path + ":" + runtime, "RunningFoldJavaConsumer.java"], root: root)
            let javaExecution = try java(["-cp", root.path + ":" + app.0.path + ":" + runtime, "RunningFoldJavaConsumer"])
            #expect(javaExecution.exitCode == 0, "Java consumer stderr: \(javaExecution.stderr)")
            #expect(javaExecution.stdout == "[0, 1, 3, 6]\n[0, 1, 3, 6]\n")
            #expect(javaExecution.stderr.isEmpty)

            let invalid = try m22Build(
                root: root,
                sources: [("InvalidRunningFold.kt", "fun main() { listOf(1).runningFold(0) { value -> value } }")],
                name: "invalid-running-fold.jar"
            )
            #expect(invalid.1 != 0, "runningFold must reject a callback with the wrong arity")
            #expect(invalid.2.contains { $0.code == "KSWIFTK-SEMA-0433" })
        }
    }
}
#endif
