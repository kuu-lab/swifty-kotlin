@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListFlatMapBasic() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            val result = values.flatMap { listOf(it, it * 10) }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionFlatMapBasic",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 10, 2, 20, 3, 30]\n")
        }
    }

    func testCodegenListFlatMapWithEmptyInput() throws {
        let source = """
        fun main() {
            val values = emptyList<Int>()
            val result = values.flatMap { listOf(it, it * 10) }
            println(result)
            println(result.size)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionFlatMapEmptyInput",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[]\n0\n")
        }
    }

    func testCodegenListFlatMapWithConditionalEmptySubList() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4, 5)
            val result = values.flatMap { if (it % 2 == 0) listOf(it) else listOf<Int>() }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionFlatMapConditionalEmpty",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[2, 4]\n")
        }
    }

    func testCodegenListFlatMapIndexed() throws {
        let source = """
        fun main() {
            val values = listOf(10, 20, 30)
            val result = values.flatMapIndexed { index, value -> listOf(index, value) }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionFlatMapIndexed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[0, 10, 1, 20, 2, 30]\n")
        }
    }
}
