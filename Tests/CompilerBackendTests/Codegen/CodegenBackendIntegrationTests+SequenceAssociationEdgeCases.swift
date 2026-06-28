@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// MARK: - STDLIB-SEQ-FN-005: Sequence.associate { T -> Pair<K, V> }

extension CodegenBackendIntegrationTests {
    func testSequenceAssociateBuildsMapWithUniqueKeys() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associate { it to it * 10 }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAssociateUniqueKeys",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "{1=10, 2=20, 3=30}\n")
        }
    }

    func testSequenceAssociateEmptySequenceReturnsEmptyMap() throws {
        let source = """
        fun main() {
            val result = emptySequence<Int>().associate { it to it * 10 }
            println(result)
            println(result.size)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAssociateEmptySeq",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "{}\n0\n")
        }
    }

    func testSequenceAssociateWithStringElementsProducesStringIntMap() throws {
        let source = """
        fun main() {
            val result = sequenceOf("a", "bb", "ccc").associate { it to it.length }
            println(result["a"])
            println(result["bb"])
            println(result["ccc"])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAssociateStringKeys",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1\n2\n3\n")
        }
    }

    func testSequenceAssociateAllowsKeyLookupInResult() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associate { it to it * it }
            println(result[1])
            println(result[2])
            println(result[3])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAssociateKeyLookup",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1
                4
                9
                """ + "\n"
            )
        }
    }

    func testSequenceAssociateWithMapsElementsToTransformedValues() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associateWith { value ->
                value * value
            }
            println(result[1])
            println(result[2])
            println(result[3])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAssociateWithRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1
                4
                9
                """ + "\n"
            )
        }
    }
}
