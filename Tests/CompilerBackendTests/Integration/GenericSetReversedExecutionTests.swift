@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct GenericSetReversedExecutionTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func run(
        source: String,
        expectedOutput: String,
        moduleName: String,
        fromSource: Bool,
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("main.kt").path
        let output = directory.appendingPathComponent("main").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        let stdlibLibraryPath = fromSource ? nil : try testStdlibArtifactPath()
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: stdlibLibraryPath,
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expectedOutput)
    }

    @Test(arguments: [false, true], [0, 2])
    func genericSetReceiverReturnsTypedReversedList(fromSource: Bool, optimization: Int) throws {
        let source = """
        fun <T> reversed(values: Set<T>): List<T> = values.reversed()
        fun main() { println(reversed(linkedSetOf("a", "b", "c"))) }
        """
        try run(
            source: source,
            expectedOutput: "[c, b, a]\n",
            moduleName: "KUU1874GenericSetReversed",
            fromSource: fromSource,
            optimization: optimization
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func originalDfsTopologicalSortRunsUnchanged(fromSource: Bool, optimization: Int) throws {
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scripts/reference_cases/kuu_1874_dfs_topological_sort.kt"
            ),
            encoding: .utf8
        )
        try run(
            source: source,
            expectedOutput: "[A, B, C, D, E, F, G, H, I]\n",
            moduleName: "KUU1874DfsTopologicalSort",
            fromSource: fromSource,
            optimization: optimization
        )
    }
}
