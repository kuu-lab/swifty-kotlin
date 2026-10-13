#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendForEachNonLocalReturnTests {

    @Test
    func testListForEachNonLocalReturnWithDefaultStdlib() throws {
        let source = """
        fun search(values: List<Int>): Int {
            values.forEach {
                if (it > 1) return it
            }
            return -1
        }

        fun filteredSearch(values: List<Int>): Int {
            values.filter { it > 0 }.forEach {
                if (it > 1) return it
            }
            return -1
        }

        fun main() {
            println(search(listOf(1, 2, 3)))
            println(filteredSearch(listOf(1, 2, 3)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListForEachNonLocalReturnDefault",
            expected: "2\n2\n"
        )
    }

    @Test
    func testSourceBackedForEachNonLocalReturns() throws {
        let source = """
        fun setSearch(values: Set<Int>): Int {
            values.forEach {
                if (it > 1) return it
            }
            return -1
        }

        fun intArraySearch(values: IntArray): Int {
            values.forEach {
                if (it > 1) return it
            }
            return -1
        }

        fun indexedSearch(values: List<Int>): Int {
            values.forEachIndexed { _, value ->
                if (value > 1) return value
            }
            return -1
        }

        fun main() {
            println(setSearch(setOf(1, 2, 3)))
            println(intArraySearch(intArrayOf(1, 2, 3)))
            println(indexedSearch(listOf(1, 2, 3)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForEachNonLocalReturnSource",
            expected: "2\n2\n2\n",
            allowDefaultStdlibLibrary: false
        )
    }

    @Test(arguments: [false, true])
    func testLongRangeForEachNonLocalReturns(usePrecompiledStdlib: Bool) throws {
        let source = try diffCaseSource("long_range_foreach_non_local_return.kt", file: #filePath)
        let stdlibLibraryPath = usePrecompiledStdlib ? try testStdlibArtifactPath() : nil
        try withTemporaryFile(contents: source) { path in
            for optLevel in [OptimizationLevel.O0, .O2] {
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = try runCodegenPipeline(
                    inputPath: path,
                    moduleName: "LongRangeForEachNonLocalReturn",
                    outputPath: output,
                    optLevel: optLevel,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: stdlibLibraryPath
                )
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "2\n222\n6\n")
                #expect(result.stderr.isEmpty)
            }
        }
    }
}
#endif
