@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCompareByVarargSelectors() throws {
        let source = """
        fun main() {
            val cmp = compareBy<Int>({ it / 100 }, { it % 100 / 10 }, { it % 10 }, { -it })
            println(listOf(231, 132, 121, 221).sortedWith(cmp))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CompareByVarargSelectors",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[121, 132, 221, 231]\n")
        }
    }

    func testCodegenCompilesCompareValuesByVarargSelectors() throws {
        let source = """
        fun main() {
            println(compareValuesBy(231, 132, { it / 100 }, { it % 100 / 10 }, { it % 10 }, { -it }))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CompareValuesByVarargSelectors",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1\n")
        }
    }

    func testCodegenCompilesComparatorThenByComparatorSelector() throws {
        let source = """
        fun main() {
            val primary = compareBy<Int> { it % 10 }
            val secondary = compareBy<Int> { it }
            val cmp = primary.thenBy(secondary) { it / 10 }
            println(listOf(23, 15, 13).sortedWith(cmp))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparatorThenByComparatorSelector",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[13, 23, 15]\n")
        }
    }

    func testCodegenCompilesCompareValuesByComparatorSelector() throws {
        let source = """
        fun main() {
            val ascending = compareBy<Int> { it }
            println(compareValuesBy(13, 25, ascending) { it % 10 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CompareValuesByComparatorSelector",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "-1\n")
        }
    }

    func testCodegenCompilesComparatorThenByDescendingComparatorSelector() throws {
        let source = """
        fun main() {
            val primary = compareBy<Int> { it % 10 }
            val secondary = compareBy<Int> { it }
            val cmp = primary.thenByDescending(secondary) { it / 10 }
            println(listOf(23, 15, 13).sortedWith(cmp))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparatorThenByDescendingComparatorSelector",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[23, 13, 15]\n")
        }
    }

    func testCodegenCompilesCompareByDescendingComparatorSelector() throws {
        let source = """
        fun main() {
            val byLength = compareByDescending<String, Int>(compareBy<Int> { it }) { it.length }
            println(listOf("pear", "fig", "apple").sortedWith(byLength))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CompareByDescendingComparatorSelector",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[apple, pear, fig]\n")
        }
    }

    func testCodegenCompilesCompareByComparatorSelector() throws {
        let source = """
        fun main() {
            val byLength = compareBy<String, Int>(compareBy<Int> { it }) { it.length }
            println(listOf("pear", "fig", "apple").sortedWith(byLength))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CompareByComparatorSelector",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[fig, pear, apple]\n")
        }
    }

    // The 1-arg composition variants (thenByDescending { selector }, thenDescending { a, b -> },
    // thenComparator { a, b -> }) share the same lowering path as thenBy: the receiver comparator
    // is expanded into a (trampolineFn, closureRaw) pair before being handed to the runtime
    // kk_comparator_then_* entry points (STDLIB-COMP-002, #3802). Only thenBy was previously
    // exercised end-to-end; these tests lock in the fix for the remaining three callees, which
    // crashed at runtime before the receiver-expansion was added.

    func testCodegenCompilesComparatorThenByDescendingSelector() throws {
        let source = """
        data class Entry(val group: Int, val score: Int)

        fun main() {
            val values = listOf(
                Entry(1, 30),
                Entry(1, 20),
                Entry(2, 10),
                Entry(2, 40),
            )
            // thenByDescending { selector }: group ascending, then score descending.
            val cmp = compareBy<Entry> { it.group }
                .thenByDescending { it.score }
            println(values.sortedWith(cmp).map { "${it.group}:${it.score}" })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparatorThenByDescendingSelector",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1:30, 1:20, 2:40, 2:10]\n")
        }
    }

    func testCodegenCompilesComparatorThenDescending() throws {
        let source = """
        data class Entry(val group: Int, val score: Int)

        fun main() {
            val values = listOf(
                Entry(1, 30),
                Entry(1, 20),
                Entry(2, 10),
                Entry(2, 40),
            )
            // thenDescending { a, b -> ... }: the comparison fn is reversed for the tie-break,
            // so an ascending score comparison becomes a descending tie-break.
            val cmp = compareBy<Entry> { it.group }
                .thenDescending { a, b -> a.score - b.score }
            println(values.sortedWith(cmp).map { "${it.group}:${it.score}" })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparatorThenDescending",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1:30, 1:20, 2:40, 2:10]\n")
        }
    }

    func testCodegenCompilesComparatorThenComparator() throws {
        let source = """
        data class Entry(val group: Int, val score: Int)

        fun main() {
            val values = listOf(
                Entry(1, 30),
                Entry(1, 20),
                Entry(2, 10),
                Entry(2, 40),
            )
            // thenComparator { a, b -> ... }: the comparison fn is used as-is for the tie-break,
            // so an ascending score comparison keeps the tie-break ascending.
            val cmp = compareBy<Entry> { it.group }
                .thenComparator { a, b -> a.score - b.score }
            println(values.sortedWith(cmp).map { "${it.group}:${it.score}" })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparatorThenComparator",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1:20, 1:30, 2:10, 2:40]\n")
        }
    }

    func testCodegenCompilesComparatorCompositionEdgeCases() throws {
        let source = """
        data class Entry(val group: Int, val score: Int)

        fun main() {
            val values = listOf(
                Entry(1, 30),
                Entry(1, 20),
                Entry(2, 10),
                Entry(2, 40),
            )

            val chained = compareBy<Entry> { it.group }
                .thenBy { -it.score }
            println(values.sortedWith(chained).map { "${it.group}:${it.score}" })

            println(values.sortedWith(chained.reversed()).map { "${it.group}:${it.score}" })

            val words = listOf("pear", "fig", "apple")
            println(words.sortedWith(reverseOrder()))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparatorCompositionEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1:30, 1:20, 2:40, 2:10]
                [2:10, 2:40, 1:20, 1:30]
                [pear, fig, apple]
                """
                + "\n"
            )
        }
    }
}
