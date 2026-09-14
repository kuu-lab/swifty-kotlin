#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendIterableSortedTests {
    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    @Test
    func testCodegenIterableSortedFamilyUsesSourceBackedDeclarations() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let cases: [(name: String, output: String)] = [
            (
                "stdlib_kotlin_collections_Iterable_sorted",
                """
                [1, 1, 2, 3]
                1
                [3, 2, 1, 1]
                1
                [a1, a2, b2, b1]
                1
                []
                [7]
                selector failed
                1
                """ + "\n"
            ),
            (
                "stdlib_kotlin_collections_Iterable_sortedByDescending",
                """
                [b2, b1, a1, a2]
                1
                """ + "\n"
            ),
            (
                "stdlib_kotlin_collections_Iterable_sortedWith",
                """
                [null, a, bb1, bb2]
                1
                comparator failed
                1
                """ + "\n"
            ),
        ]

        for (index, testCase) in cases.enumerated() {
            let sourceURL = root.appendingPathComponent(
                "Scripts/diff_cases/\(testCase.name).kt",
                isDirectory: false
            )
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            try withTemporaryFile(contents: source) { path in
                let outputBase = FileManager.default.temporaryDirectory
                    .appendingPathComponent("iterable-sorted-\(index)-\(UUID().uuidString)")
                    .path
                let ctx = try runCodegenPipeline(
                    inputPath: path,
                    moduleName: "IterableSorted\(index)",
                    outputPath: outputBase
                )
                try LinkPhase().run(ctx)
                let result = try CommandRunner.run(executable: outputBase, arguments: [])
                let stdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                #expect(stdout == testCase.output, "Unexpected output for \(testCase.name)")
            }
        }
    }
}
#endif
