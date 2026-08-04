#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendComparableUserDefinedClassEdgeCasesTests {

    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        emit: EmitMode,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: emit,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenComparisonOperatorsDispatchUserDefinedCompareToThroughGenericBound() throws {
        let source = """
        class Version(val major: Int, val minor: Int) : Comparable<Version> {
            override fun compareTo(other: Version): Int {
                val byMajor = major.compareTo(other.major)
                return if (byMajor != 0) byMajor else minor.compareTo(other.minor)
            }
        }

        fun <T : Comparable<T>> larger(a: T, b: T): T = if (a >= b) a else b

        fun main() {
            val v1 = Version(1, 2)
            val v2 = Version(1, 5)
            println(v1 < v2)
            println(v1 > v2)
            println(larger(v1, v2).minor)
            println(larger(v2, v1).minor)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparisonOperatorsUserDefinedCompareToThroughGenericBound",
            expected:
                """
                true
                false
                5
                5

                """
        )
    }

    @Test
    func testCodegenComparableMaxOfMinOfDispatchUserDefinedCompareTo() throws {
        let source = """
        class Version(val major: Int, val minor: Int) : Comparable<Version> {
            override fun compareTo(other: Version): Int {
                val byMajor = major.compareTo(other.major)
                return if (byMajor != 0) byMajor else minor.compareTo(other.minor)
            }
            override fun toString(): String = "$major.$minor"
        }

        fun main() {
            val v1 = Version(1, 2)
            val v2 = Version(1, 5)
            println(maxOf(v1, v2))
            println(minOf(v1, v2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparableMaxOfMinOfUserDefinedCompareTo",
            expected:
                """
                1.5
                1.2

                """
        )
    }
}
#endif
