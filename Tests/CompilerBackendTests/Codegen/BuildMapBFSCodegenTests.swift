#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct BuildMapBFSCodegenTests {
    @Test(arguments: [false, true], [0, 2])
    func queueApplyAndDestructuredLetExecute(useLibrary: Bool, optimization: Int) throws {
        let optLevel: OptimizationLevel = optimization == 0 ? .O0 : .O2
        let source = try diffCaseSource("build_map_queue_bfs.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "BuildMapQueueBFS",
            expected: "[0]\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: useLibrary
        )
        try assertKotlinOutput(
            source.replacingOccurrences(of: "= buildMap {", with: "= buildMap<Point,Int> {"),
            moduleName: "BuildMapExplicitQueueBFS",
            expected: "[0]\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: useLibrary
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func originalCountStepsBodyTraversesGarden(useLibrary: Bool, optimization: Int) throws {
        let optLevel: OptimizationLevel = optimization == 0 ? .O0 : .O2
        try assertKotlinOutput(
            diffCaseSource("build_map_day21_count_steps.kt", file: #filePath),
            moduleName: "BuildMapDay21CountSteps",
            expected: """
            []
            [0]
            [0, 1, 1, 2, 2, 2]
            [0, 1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6]
            [0, 1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 10, 10, 10, 10, 10, 10, 10, 10]
            """ + "\n",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: useLibrary
        )
    }
}
#endif
