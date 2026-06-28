@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // STDLIB-TEXT-TYPE-008: MatchGroupCollection interface — index access, named access, size
    func testMatchGroupCollectionIndexAccess() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\w+)-(\\\\w+)")
            val m = r.find("hello-world")
            println(m?.groups?.get(0)?.value)
            println(m?.groups?.get(1)?.value)
            println(m?.groups?.get(2)?.value)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MatchGroupCollectionIndex",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                hello-world
                hello
                world
                """ + "\n"
            )
        }
    }

    func testMatchGroupCollectionNamedAccess() throws {
        let source = """
        fun main() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})")
            val m = r.find("2025-06-09")
            println(m?.groups?.get("year")?.value)
            println(m?.groups?.get("month")?.value)
            println(m?.groups?.get("day")?.value)
            println(m?.groups?.get("missing"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MatchGroupCollectionNamed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                2025
                06
                09
                null
                """ + "\n"
            )
        }
    }

    func testMatchGroupCollectionSize() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\w+)-(\\\\w+)-(\\\\w+)")
            val m = r.find("a-b-c")
            println(m?.groups?.size)
            val r2 = Regex("\\\\w+")
            val m2 = r2.find("hello")
            println(m2?.groups?.size)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MatchGroupCollectionSize",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                4
                1
                """ + "\n"
            )
        }
    }

    func testMatchGroupCollectionOutOfBoundsReturnsNull() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\d+)")
            val m = r.find("42")
            println(m?.groups?.get(0)?.value)
            println(m?.groups?.get(99))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MatchGroupCollectionOutOfBounds",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                42
                null
                """ + "\n"
            )
        }
    }
}
