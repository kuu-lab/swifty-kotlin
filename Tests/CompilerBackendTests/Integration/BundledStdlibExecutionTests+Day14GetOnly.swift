@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testForwardSingletonInitializationRemainsLazy(
        useStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("forward_companion_initialization.kt", file: #filePath),
            expectedOutput: "0\n9\n0\n-1\n1\n-1\n1\n42\n2\n41\n2\ncaught\n7\n",
            moduleName: "KUU2036ForwardSingletonInitialization",
            allowDefaultStdlibLibrary: useStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func testDay14GetOnlyWithOriginalPointSourceAndArtifact(
        useStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/aoc-day14-get-only")
        let sources = try ["Grid.kt", "Point2D.kt"].map {
            try String(contentsOf: fixtures.appendingPathComponent($0), encoding: .utf8)
        }
        try compileAndRunKotlinSources(
            sources,
            expectedOutput: "done\n",
            moduleName: "KUU2036Day14GetOnly",
            allowDefaultStdlibLibrary: useStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
