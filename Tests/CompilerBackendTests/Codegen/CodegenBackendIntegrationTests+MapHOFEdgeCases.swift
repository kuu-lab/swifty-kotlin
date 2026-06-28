@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    // MARK: - getOrDefault

    func testCodegenMapGetOrDefaultReturnsExistingKey() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2)
            println(map.getOrDefault("a", 99))
            println(map.getOrDefault("b", 99))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapGetOrDefaultKeyPresent",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1\n2\n")
        }
    }

    func testCodegenMapGetOrDefaultReturnsDefaultWhenKeyAbsent() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2)
            println(map.getOrDefault("z", 99))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapGetOrDefaultKeyAbsent",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "99\n")
        }
    }

    func testCodegenMapGetOrDefaultWithEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            println(empty.getOrDefault("key", 42))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapGetOrDefaultEmptyMap",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "42\n")
        }
    }

    // MARK: - flatMap

    func testCodegenMapFlatMapTransformsAllEntries() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2)
            val result = map.flatMap { listOf("${it.key}:${it.value}") }
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapFlatMapTransformsAllEntries",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[a:1, b:2]\n")
        }
    }

    func testCodegenMapFlatMapWithEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            val result = empty.flatMap { listOf("${it.key}:${it.value}") }
            println(result)
            println(result.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapFlatMapEmptyMap",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[]\n0\n")
        }
    }

    // MARK: - mapNotNull

    func testCodegenMapMapNotNullFiltersNullResults() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2, "c" to 3)
            val result = map.mapNotNull { if (it.value > 1) "${it.key}:${it.value}" else null }
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapMapNotNullFiltersNulls",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[b:2, c:3]\n")
        }
    }

    func testCodegenMapMapNotNullWithEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            val result = empty.mapNotNull { "${it.key}:${it.value}" }
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapMapNotNullEmptyMap",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[]\n")
        }
    }

    // MARK: - maxByOrNull

    func testCodegenMapMaxByOrNullReturnsNullForEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            val result = empty.maxByOrNull { it.value }
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapMaxByOrNullEmptyMap",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "null\n")
        }
    }

    func testCodegenMapMaxByOrNullReturnsEntryWithMaxSelector() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 3, "c" to 2)
            val entry = map.maxByOrNull { it.value }
            println(entry?.key)
            println(entry?.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapMaxByOrNullNonEmpty",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "b\n3\n")
        }
    }

    // MARK: - minByOrNull

    func testCodegenMapMinByOrNullReturnsNullForEmptyMap() throws {
        let source = """
        fun main() {
            val empty = emptyMap<String, Int>()
            val result = empty.minByOrNull { it.value }
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapMinByOrNullEmptyMap",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "null\n")
        }
    }

    func testCodegenMapMinByOrNullReturnsEntryWithMinSelector() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 3, "b" to 1, "c" to 2)
            val entry = map.minByOrNull { it.value }
            println(entry?.key)
            println(entry?.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapMinByOrNullNonEmpty",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "b\n1\n")
        }
    }
}
