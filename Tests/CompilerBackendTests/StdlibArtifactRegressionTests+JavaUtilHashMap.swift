@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    /// KUU-2234/KUU-2401: Java-FQN HashMap imports reuse the Kotlin HashMap
    /// API, copy entries, and preserve runtime identity across stdlib surfaces.
    @Test
    func testJavaUtilHashMapFacadeRunsAcrossSourceAndArtifact() throws {
        let source = """
        import java.util.HashMap
        import java.util.HashMap as JavaHashMap
        import kotlin.collections.HashMap as KotlinHashMap

        private fun capacityHashMap(size: Int): HashMap<String, Int> = HashMap(size, 1.0F)

        private fun asKotlinMap(value: HashMap<String, Int>): KotlinHashMap<String, Int> = value
        private fun asJavaMap(value: KotlinHashMap<String, Int>): JavaHashMap<String, Int> = value

        fun main() {
            val source = JavaHashMap<String, Int>(8, 1.0F)
            source["answer"] = 42
            val copied: HashMap<String, Int> = HashMap(source)
            val copiedAlias: JavaHashMap<String, Int> = JavaHashMap(source)

            val kotlinMap: KotlinHashMap<String, Int> = asKotlinMap(source)
            val backToJava: JavaHashMap<String, Int> = asJavaMap(kotlinMap)
            val mutableMap: MutableMap<String, Int> = backToJava

            val capacityOnly = HashMap<String, Int>(8)
            capacityOnly["capacity"] = 8

            val noImportKotlinMap: kotlin.collections.HashMap<String, Int> =
                kotlin.collections.HashMap()
            noImportKotlinMap["control"] = 7

            val erasedJava: Any = source
            val erasedKotlin: Any = noImportKotlinMap

            println(capacityHashMap(8).size)
            println(copied == source)
            println(copied["answer"])
            println(copiedAlias == source)
            println(copiedAlias["answer"])
            println(kotlinMap === source)
            println(backToJava === source)
            println(erasedJava is KotlinHashMap<*, *>)
            println(erasedKotlin is JavaHashMap<*, *>)
            println(mutableMap["answer"])
            println(capacityOnly["capacity"])
            println(noImportKotlinMap["control"])
        }
        """
        let expected = """
        0
        true
        42
        true
        42
        true
        true
        true
        true
        42
        8
        7

        """
        let artifactPath = try Self.buildStdlibArtifact()

        for (surface, libraryPath) in [("source", nil), ("fresh .kklib", artifactPath)] {
            for optLevel in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { input in
                    let output = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .path
                    defer {
                        try? FileManager.default.removeItem(atPath: output)
                        try? FileManager.default.removeItem(atPath: output + ".o")
                    }

                    let context = makeJavaUtilHashMapContext(
                        input: input,
                        output: output,
                        libraryPath: libraryPath,
                        emit: .executable,
                        optLevel: optLevel
                    )
                    do {
                        try runToKIR(context)
                        try assertNoDiagnosticErrors(context)
                        try LoweringPhase().run(context)
                        try CodegenPhase().run(context)
                        try LinkPhase().run(context)
                    } catch {
                        throw CompilerPipelineError.invalidInput(
                            "\(surface) \(optLevel) pipeline failed: \(error); "
                                + "diagnostics: \(context.diagnostics.diagnostics)"
                        )
                    }

                    let result: CommandResult
                    do {
                        result = try CommandRunner.run(executable: output, arguments: [])
                    } catch {
                        throw CompilerPipelineError.invalidInput(
                            "\(surface) \(optLevel) execution failed: \(error)"
                        )
                    }
                    #expect(result.exitCode == 0, "\(surface), \(optLevel): \(result.stderr)")
                    #expect(
                        result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                        "Unexpected \(surface) output at \(optLevel)"
                    )
                }
            }
        }
    }
}

private func makeJavaUtilHashMapContext(
    input: String,
    output: String,
    libraryPath: String?,
    emit: EmitMode,
    optLevel: OptimizationLevel
) -> CompilationContext {
    CompilationContext(
        options: CompilerOptions(
            moduleName: "KUU2401JavaUtilHashMap",
            inputs: [input],
            outputPath: output,
            emit: emit,
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: optLevel,
            includeStdlib: libraryPath == nil,
            stdlibLibraryPath: libraryPath,
            allowDefaultStdlibLibrary: false
        ),
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
}
