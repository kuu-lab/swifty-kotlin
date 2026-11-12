#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func intArrayFoldIndexedMatchesKotlincAndJavaConsumer() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repository.appendingPathComponent("Scripts/diff_cases/int_array_fold_indexed.kt")
        let expected = try String(contentsOf: repository.appendingPathComponent("Scripts/diff_cases/int_array_fold_indexed.expected"), encoding: .utf8)
        let source = try String(contentsOf: fixture, encoding: .utf8)

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("FoldIndexed.kt", source)],
                name: "fold-indexed.jar",
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let candidate = try java(["-cp", app.0.path + ":" + runtime, "FoldIndexedKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            let referenceCompile = try jvmTool("kotlinc", ["-cp", runtime, "FoldIndexed.kt", "-d", "reference.jar"], root: root)
            try #require(referenceCompile.exitCode == 0, "\(referenceCompile.stderr)")
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "FoldIndexedKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)

            try """
            public final class IntArrayFoldIndexedConsumer {
                public static void main(String[] args) {
                    int result = FoldIndexedKt.weightedSum();
                    if (result != 8) throw new AssertionError("Unexpected result: " + result);
                    System.out.println(result);
                }
            }
            """.write(to: root.appendingPathComponent("IntArrayFoldIndexedConsumer.java"), atomically: true, encoding: .utf8)
            let javaCompile = try jvmTool("javac", ["-cp", app.0.path + ":" + runtime, "IntArrayFoldIndexedConsumer.java"], root: root)
            try #require(javaCompile.exitCode == 0, "\(javaCompile.stderr)")
            let javaConsumer = try java(["-cp", root.path + ":" + app.0.path + ":" + runtime, "IntArrayFoldIndexedConsumer"])
            #expect(javaConsumer.stdout == "8\n")
            #expect(javaConsumer.stderr.isEmpty)
        }
    }

    @Test
    func intArrayFoldIndexedRejectsMissingInitialValue() throws {
        let invalid = """
        fun main() {
            intArrayOf(1).foldIndexed { index, acc, value -> acc + index + value }
        }
        """

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("FoldIndexed.kt", invalid)],
                name: "invalid.jar",
                classpath: runtime.components(separatedBy: ":")
            )
            #expect(app.1 != 0)
            #expect(app.2.contains { $0.message.contains("No value passed for parameter 'initial'") })

            let reference = try jvmTool("kotlinc", ["-cp", runtime, "FoldIndexed.kt", "-d", "invalid-reference.jar"], root: root)
            #expect(reference.exitCode != 0)
        }
    }
}
#endif
