@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// KSP-INF-006: bundled `.kt` 自己完結実行テストハーネス。
/// Kotlin ソースを executable までコンパイルし、実行後の stdout を期待値と比較する。
/// kotlinc を使わない第二 oracle として機能する。
@Suite
struct BundledStdlibExecutionTests {
    private struct ExecutionFailure: Error, CustomStringConvertible {
        let description: String
    }

    /// Compile `source` to an executable, run it, and assert stdout equals `expectedOutput`.
    private func compileAndRunKotlin(
        _ source: String,
        expectedOutput: String,
        moduleName: String = "ExecTest"
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let fm = FileManager.default
            let outputBase = fm.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? fm.removeItem(atPath: outputBase) }

            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: [path],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let result = makeTestDriver().runForTesting(options: options)

            guard result.exitCode == 0 else {
                let diagnostics = result.diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: ", ")
                throw ExecutionFailure(
                    description: "Compilation failed. Diagnostics: \(diagnostics)"
                )
            }
            guard !result.diagnostics.contains(where: { $0.severity == .error }) else {
                let errors = result.diagnostics
                    .filter { $0.severity == .error }
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: ", ")
                throw ExecutionFailure(description: "Unexpected errors: \(errors)")
            }

            let runResult = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalized = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalized == expectedOutput,
                "Expected stdout '\(expectedOutput)' but got '\(normalized)'"
            )
        }
    }

    @Test
    func testHelloWorldPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println("hello")
            }
            """,
            expectedOutput: "hello\n"
        )
    }

    @Test
    func testForInRangePrintsSequence() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                for (i in 1..4) {
                    print(i)
                }
                println()
            }
            """,
            expectedOutput: "1234\n"
        )
    }

    @Test
    func testListFilterMapPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val result = listOf(1, 2, 3, 4)
                    .filter { it > 1 }
                    .map { it * 2 }
                    .joinToString("-")
                println(result)
            }
            """,
            expectedOutput: "4-6-8\n"
        )
    }

    @Test
    func testListSortedPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val result = listOf(3, 1, 4, 1, 5)
                    .sorted()
                    .joinToString(",")
                println(result)
            }
            """,
            expectedOutput: "1,1,3,4,5\n"
        )
    }

    // KSP-INF-011 regression: List<Int>.joinToString must render integers, not
    // fall back to the string-only runtime fast path and produce empty output.
    @Test
    func testListIntJoinToStringWithTransformPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(listOf(1, 2, 3).joinToString("-", "[", "]") { it.toString() })
            }
            """,
            expectedOutput: "[1-2-3]\n"
        )
    }

    // KSP-INF-011 regression: Array<Int>.joinToString must also render generic
    // element types through the guarded default overload.
    @Test
    func testArrayIntJoinToStringPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(arrayOf(7, 8, 9).joinToString("-"))
            }
            """,
            expectedOutput: "7-8-9\n"
        )
    }
}
