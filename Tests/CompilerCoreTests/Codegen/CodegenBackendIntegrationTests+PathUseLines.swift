@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-IO-PATH-FN-038: kotlin.io.path.Path.useLines codegen tests
extension CodegenBackendIntegrationTests {

    // MARK: - Path.useLines {} — count

    func testCodegenPathUseLinesCount() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_count.txt")
            path.deleteIfExists()
            path.writeText("alpha\\nbeta\\ngamma")

            val count = path.useLines { lines ->
                lines.count()
            }
            println(count)

            path.deleteIfExists()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PathUseLinesCount",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalized = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalized, "3\n")
        }
    }

    // MARK: - Path.useLines {} — forEach

    func testCodegenPathUseLinesForEach() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_foreach.txt")
            path.deleteIfExists()
            path.writeText("one\\ntwo\\nthree")

            path.useLines { lines ->
                lines.forEach { line -> println(line) }
            }

            path.deleteIfExists()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PathUseLinesForEach",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalized = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalized, "one\ntwo\nthree\n")
        }
    }

    // MARK: - Path.useLines {} — empty file

    func testCodegenPathUseLinesEmptyFile() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_empty.txt")
            path.deleteIfExists()
            path.writeText("")

            val count = path.useLines { lines ->
                lines.count()
            }
            println(count)

            path.deleteIfExists()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PathUseLinesEmpty",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalized = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalized, "0\n")
        }
    }

    // MARK: - Path.useLines {} — block return value (toList)

    func testCodegenPathUseLinesReturnsList() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_tolist.txt")
            path.deleteIfExists()
            path.writeText("x\\ny\\nz")

            val lines: List<String> = path.useLines { it.toList() }
            println(lines.size)
            lines.forEach { println(it) }

            path.deleteIfExists()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PathUseLinesReturnsList",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalized = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalized, "3\nx\ny\nz\n")
        }
    }
}
