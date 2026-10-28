@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// Pinned upstream consumer: https://github.com/DmitryTsyvtsyn/Kotlin-Algorithms-and-Design-Patterns/blob/1f89f062a056e24cc289ffdd0c6e23cadf8df887/src/main/kotlin/structures/Stack1.kt
    /// KUU-1857: `java.util.ArrayList` imports and aliases reuse the native
    /// Kotlin ArrayList while preserving generic element types and constructors.
    @Test
    func testJavaUtilArrayListImportAndAliasAcrossStdlibSurfaces() throws {
        let source = """
        import java.util.ArrayList
        import java.util.ArrayList as NativeArrayList

        private fun lastString(values: NativeArrayList<String>): String = values.last()

        fun main() {
            val values = ArrayList<String>()
            values.add("a")
            values.add("b")
            println(values.removeLast())
            println(values.joinToString(","))

            val aliased: NativeArrayList<String> = NativeArrayList()
            aliased.add("alias")
            println(lastString(aliased))
            val kotlinArrayList: kotlin.collections.ArrayList<String> = aliased
            println(kotlinArrayList.size == 1)

            val imported: ArrayList<String> = ArrayList()
            imported.add("fqn")
            println(lastString(imported))

            values.clear()
            println(values.isEmpty())
            try {
                values.removeLast()
            } catch (error: NoSuchElementException) {
                println(error.message)
            }
            try {
                values.removeAt(0)
            } catch (_: IndexOutOfBoundsException) {
                println("bounds")
            }
        }
        """
        let expected = """
        b
        a
        alias
        true
        fqn
        true
        null
        bounds

        """
        let artifactPath = try Self.buildStdlibArtifact()

        for (surface, libraryPath) in [("source", nil), ("fresh .kklib", artifactPath)] {
            for optimizationLevel in [OptimizationLevel.O0, .O2] {
                let output = try runJavaUtilArrayListConsumer(
                    source,
                    moduleName: "KUU1857ArrayList_\(surface)_\(optimizationLevel.rawValue)",
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

private func runJavaUtilArrayListConsumer(
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
