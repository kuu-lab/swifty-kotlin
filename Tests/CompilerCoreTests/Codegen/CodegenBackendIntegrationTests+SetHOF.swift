@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSetFilterKeepsMatchingElements() throws {
        let source = """
        fun main() {
            val s = setOf(1, 2, 3, 4)
            println(s.filter { it % 2 == 0 })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetFilter", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "[2, 4]\n")
        }
    }

    func testCodegenSetFilterEmptySetReturnsEmptyList() throws {
        let source = """
        fun main() {
            val s = setOf<Int>()
            println(s.filter { it > 0 })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetFilterEmpty", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "[]\n")
        }
    }

    func testCodegenSetFilterNotExcludesMatchingElements() throws {
        let source = """
        fun main() {
            val s = setOf(1, 2, 3, 4)
            println(s.filterNot { it % 2 == 0 })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetFilterNot", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "[1, 3]\n")
        }
    }

    func testCodegenSetMapTransformsAllElements() throws {
        let source = """
        fun main() {
            val s = setOf(1, 2, 3)
            println(s.map { it * 2 })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetMap", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "[2, 4, 6]\n")
        }
    }

    func testCodegenSetFlatMapFlattensSubCollections() throws {
        let source = """
        fun main() {
            val s = setOf(1, 2)
            println(s.flatMap { listOf(it, it * 10) })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetFlatMap", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "[1, 10, 2, 20]\n")
        }
    }

    func testCodegenSetAllReturnsTrueOnlyWhenAllElementsMatch() throws {
        let source = """
        fun main() {
            println(setOf(2, 4, 6).all { it % 2 == 0 })
            println(setOf(1, 2, 3).all { it % 2 == 0 })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetAll", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "true\nfalse\n")
        }
    }

    func testCodegenSetAnyReturnsTrueWhenAtLeastOneElementMatches() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).any { it > 2 })
            println(setOf(1, 2, 3).any { it > 10 })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetAny", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "true\nfalse\n")
        }
    }

    func testCodegenSetForEachAccumulatesSideEffects() throws {
        let source = """
        fun main() {
            var sum = 0
            setOf(1, 2, 3).forEach { sum += it }
            println(sum)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetForEach", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "6\n")
        }
    }

    func testCodegenSetMaxOrNullReturnsMaximumElement() throws {
        let source = """
        fun main() {
            println(setOf(3, 1, 4, 2).maxOrNull())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetMaxOrNull", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "4\n")
        }
    }

    func testCodegenSetMaxOrNullEmptySetReturnsNull() throws {
        let source = """
        fun main() {
            println(setOf<Int>().maxOrNull())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetMaxOrNullEmpty", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "null\n")
        }
    }

    func testCodegenSetMinOrNullReturnsMinimumElement() throws {
        let source = """
        fun main() {
            println(setOf(3, 1, 4, 2).minOrNull())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetMinOrNull", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "1\n")
        }
    }

    func testCodegenSetMinOrNullEmptySetReturnsNull() throws {
        let source = """
        fun main() {
            println(setOf<Int>().minOrNull())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetMinOrNullEmpty", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "null\n")
        }
    }

    func testCodegenSetSortedReturnsElementsInAscendingOrder() throws {
        let source = """
        fun main() {
            println(setOf(3, 1, 4, 2).sorted())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetSorted", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "[1, 2, 3, 4]\n")
        }
    }

    func testCodegenSetSortedDescendingReturnsElementsInDescendingOrder() throws {
        let source = """
        fun main() {
            println(setOf(3, 1, 4, 2).sortedDescending())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetSortedDescending", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "[4, 3, 2, 1]\n")
        }
    }

    func testCodegenSetCountPredicateCountsMatchingElements() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3, 4).count { it % 2 == 0 })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetCountPredicate", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "2\n")
        }
    }

    func testCodegenSetFirstReturnsFirstInsertionOrderElement() throws {
        let source = """
        fun main() {
            println(setOf(10, 20, 30).first())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetFirst", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "10\n")
        }
    }

    func testCodegenSetFirstOnEmptySetThrowsNoSuchElementException() throws {
        let source = """
        fun main() {
            try {
                setOf<Int>().first()
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetFirstEmpty", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "empty\n")
        }
    }

    func testCodegenSetLastReturnsLastInsertionOrderElement() throws {
        let source = """
        fun main() {
            println(setOf(10, 20, 30).last())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetLast", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "30\n")
        }
    }

    func testCodegenSetLastOnEmptySetThrowsNoSuchElementException() throws {
        let source = """
        fun main() {
            try {
                setOf<Int>().last()
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetLastEmpty", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "empty\n")
        }
    }

    func testCodegenSetLastOrNullEmptySetReturnsNull() throws {
        let source = """
        fun main() {
            println(setOf<Int>().lastOrNull())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetLastOrNullEmpty", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "null\n")
        }
    }

    func testCodegenSetLastOrNullNonEmptyReturnsLastElement() throws {
        let source = """
        fun main() {
            println(setOf(10, 20, 30).lastOrNull())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetLastOrNullNonEmpty", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "30\n")
        }
    }

    func testCodegenSetSingleOrNullSingleElementReturnsThatElement() throws {
        let source = """
        fun main() {
            println(setOf(42).singleOrNull())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetSingleOrNull", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "42\n")
        }
    }

    func testCodegenSetSingleOrNullMultipleElementsReturnsNull() throws {
        let source = """
        fun main() {
            println(setOf(1, 2).singleOrNull())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(inputPath: path, moduleName: "SetSingleOrNullMultiple", emit: .executable, outputPath: outputBase)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(result.stdout.replacingOccurrences(of: "\r\n", with: "\n"), "null\n")
        }
    }
}
