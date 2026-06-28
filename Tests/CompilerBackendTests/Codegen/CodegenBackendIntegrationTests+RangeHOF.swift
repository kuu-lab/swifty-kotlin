@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenIntRangeMapIndexed() throws {
        let source = """
        fun main() {
            println((1..4).mapIndexed { index, value -> index + value })
            println((1..1).mapIndexed { index, value -> index + value })
            println((1..0).mapIndexed { index, value -> index + value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IntRangeMapIndexed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                """
                [1, 3, 5, 7]
                [1]
                []
                """ + "\n"
            )
        }
    }

    func testCodegenIntRangeMapNotNull() throws {
        let source = """
        fun main() {
            println((1..5).mapNotNull { if (it % 2 == 0) null else it })
            println((2..2).mapNotNull { if (it % 2 == 0) null else it })
            println((1..0).mapNotNull { if (it % 2 == 0) null else it })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IntRangeMapNotNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                """
                [1, 3, 5]
                []
                []
                """ + "\n"
            )
        }
    }

    func testCodegenIntRangeFilterIndexed() throws {
        let source = """
        fun main() {
            println((1..4).filterIndexed { index, _ -> index % 2 == 0 })
            println((10..13).filterIndexed { index, value -> index == 0 || value > 11 })
            println((1..0).filterIndexed { index, _ -> index % 2 == 0 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IntRangeFilterIndexed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                """
                [1, 3]
                [10, 12, 13]
                []
                """ + "\n"
            )
        }
    }

    func testCodegenIntRangeFindLast() throws {
        let source = """
        fun main() {
            println((1..6).findLast { it % 2 == 0 })
            println((1..5).findLast { it > 10 })
            println((1..0).findLast { it % 2 == 0 })
            println((3..3).findLast { it == 3 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IntRangeFindLast",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                """
                6
                null
                null
                3
                """ + "\n"
            )
        }
    }

    func testCodegenIntRangeReduceIndexed() throws {
        // reduceIndexed starts with acc=first, then calls lambda with index starting at 1.
        // (1..4): acc=1, (idx=1,acc=1,val=2)→4, (idx=2,acc=4,val=3)→9, (idx=3,acc=9,val=4)→16
        // (5..5): single element, acc=5, no iterations → 5
        let source = """
        fun main() {
            println((1..4).reduceIndexed { index, acc, value -> acc + index + value })
            println((5..5).reduceIndexed { index, acc, value -> acc + index + value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IntRangeReduceIndexed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                """
                16
                5
                """ + "\n"
            )
        }
    }

    func testCodegenIntRangeMapIndexedOnDescendingProgression() throws {
        // (5 downTo 3) = [5,4,3]; mapIndexed {index+value} = [0+5,1+4,2+3] = [5,5,5]
        let source = """
        fun main() {
            println((5 downTo 3).mapIndexed { index, value -> index + value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IntRangeMapIndexedDescending",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                "[5, 5, 5]\n"
            )
        }
    }

    func testCodegenLongRangeHOFExecution() throws {
        let source = """
        fun main() {
            println((1L..4L).mapIndexed { index, value -> index + value })
            println((1L..1L).mapIndexed { index, value -> index + value })
            println((1L..0L).mapIndexed { index, value -> index + value })

            println((1L..5L).mapNotNull { if (it % 2L == 0L) null else it })
            println((2L..2L).mapNotNull { if (it % 2L == 0L) null else it })
            println((1L..0L).mapNotNull { if (it % 2L == 0L) null else it })

            println((1L..4L).filterIndexed { index, _ -> index % 2 == 0 })
            println((10L..13L).filterIndexed { index, value -> index == 0 || value > 11L })
            println((1L..0L).filterIndexed { index, _ -> index % 2 == 0 })

            println((1L..6L).findLast { it % 2L == 0L })
            println((1L..5L).findLast { it > 10L })
            println((1L..0L).findLast { it % 2L == 0L })
            println((3L..3L).findLast { it == 3L })

            println((1L..4L).reduceIndexed { index, acc, value -> acc + index + value })
            println((5L..5L).reduceIndexed { index, acc, value -> acc + index + value })

            println((5L downTo 1L).first { it % 2L == 0L })
            println((5L downTo 1L).last { it % 2L == 0L })
            println((5L downTo 3L).mapIndexed { index, value -> index + value })
            println((1L..4L).average())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "LongRangeHOFExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                """
                [1, 3, 5, 7]
                [1]
                []
                [1, 3, 5]
                []
                []
                [1, 3]
                [10, 12, 13]
                []
                6
                null
                null
                3
                16
                5
                4
                2
                [5, 5, 5]
                2.5
                """ + "\n"
            )
        }
    }
}
