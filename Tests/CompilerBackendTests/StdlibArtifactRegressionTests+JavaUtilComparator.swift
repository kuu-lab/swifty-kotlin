@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// KUU-2225: Java and Kotlin Comparator names share one contravariant SAM type.
    @Test
    func testJavaUtilComparatorAliasPreservesTypeIdentityAndVarianceAcrossStdlibSurfaces() throws {
        let source = """
        import java.util.Comparator
        import kotlin.Comparator as KotlinComparator

        private class Record(val key: Int)

        private fun compareAsJava(comparator: Comparator<Record>): Int =
            comparator.compare(Record(1), Record(2))

        private fun compareAsKotlin(comparator: KotlinComparator<Record>): Int =
            comparator.compare(Record(1), Record(2))

        fun main() {
            val javaComparator = Comparator<Record> { left, right -> left.key.compareTo(right.key) }
            val kotlinComparator: KotlinComparator<Record> = javaComparator
            val javaAgain: Comparator<Record> = kotlinComparator
            println(compareAsJava(kotlinComparator))
            println(compareAsKotlin(javaAgain))

            val broadJava: Comparator<Any> = Comparator<Any> { _, _ -> -7 }
            val narrowKotlin: KotlinComparator<Record> = broadJava
            println(narrowKotlin.compare(Record(1), Record(2)))

            val broadKotlin: KotlinComparator<Any> = KotlinComparator<Any> { _, _ -> -9 }
            val narrowJava: Comparator<Record> = broadKotlin
            println(narrowJava.compare(Record(1), Record(2)))
        }
        """
        let expected = "-1\n-1\n-7\n-9\n"
        let artifactPath = try Self.buildStdlibArtifact()

        for (surface, libraryPath) in [("source", nil), ("fresh .kklib", artifactPath)] {
            for optimizationLevel in [OptimizationLevel.O0, .O2] {
                let output = try runJavaUtilComparatorConsumer(
                    source,
                    moduleName: "KUU2225Comparator_\(surface)_\(optimizationLevel.rawValue)",
                    stdlibLibraryPath: libraryPath,
                    optLevel: optimizationLevel
                )
                #expect(
                    output == expected,
                    "Unexpected output using \(surface) at \(optimizationLevel): \(String(reflecting: output))"
                )
            }
        }
    }
}

private func runJavaUtilComparatorConsumer(
    _ source: String,
    moduleName: String,
    stdlibLibraryPath: String?,
    optLevel: OptimizationLevel
) throws -> String {
    var output = ""
    try withTemporaryFile(contents: source) { inputPath in
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        defer { try? FileManager.default.removeItem(atPath: outputBase) }

        let context = CompilationContext(
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [inputPath],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: stdlibLibraryPath == nil,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(context)
        try assertNoDiagnosticErrors(context)
        try LoweringPhase().run(context)
        try CodegenPhase().run(context)
        try LinkPhase().run(context)

        let result = try CommandRunner.run(executable: outputBase, arguments: [])
        guard result.exitCode == 0 else {
            throw TestCompilationFailure(
                description: "Execution failed with exit \(result.exitCode): \(result.stderr)"
            )
        }
        output = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
    }
    return output
}
