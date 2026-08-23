@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendSequenceToMapTests {
    private let pipelineHelper = CodegenBackendTestSupport()

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try pipelineHelper.runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: EmitMode.executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testSequenceToMapMatchesCanonicalDiffCase() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Scripts")
            .appendingPathComponent("diff_cases")
            .appendingPathComponent("stdlib_kotlin_collections_Sequence_n.kt")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "SequenceToMapRuntime",
            expected:
                """
                {first=3, second=2}
                true
                {existing=0, first=3, second=2}
                {null=2, x=1}
                {keep=7}
                """ + "\n"
        )
    }

    @Test
    func testSequenceToMapEvaluatesPairsOnceAndHonorsOneShotSequence() throws {
        let source = """
        fun main() {
            var pairEvaluations = 0
            val destination = mutableMapOf<Int, Int>()
            sequenceOf(1, 2, 3).map {
                pairEvaluations += 1
                it to it
            }.toMap(destination)
            println(pairEvaluations)
            println(destination)

            val oneShot = listOf(1 to "one", 2 to "two").iterator().asSequence()
            println(oneShot.toMap())
            try {
                oneShot.toMap()
                println("unexpected")
            } catch (error: IllegalStateException) {
                println("one-shot")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceToMapOneShotRuntime",
            expected: "3\n{1=1, 2=2, 3=3}\n{1=one, 2=two}\none-shot\n"
        )
    }
}
#endif
