@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    /// KUU-2234: Java-FQN HashMap imports reuse the Kotlin HashMap API and
    /// runtime identity through both source stdlib and a fresh .kklib.
    @Test
    func testJavaUtilHashMapFacadeCompilesFromArtifactAndRunsFromSource() throws {
        let source = """
        import java.util.HashMap
        import java.util.HashMap as JavaHashMap
        import kotlin.collections.HashMap as KotlinHashMap

        private fun capacityHashMap(size: Int): HashMap<String, Int> = HashMap(size, 1.0F)

        private fun asKotlinMap(value: HashMap<String, Int>): KotlinHashMap<String, Int> = value
        private fun asJavaMap(value: KotlinHashMap<String, Int>): JavaHashMap<String, Int> = value

        fun main() {
            val javaMap = HashMap<String, Int>(8, 1.0F)
            javaMap["answer"] = 42
            val copied: HashMap<String, Int> = HashMap(javaMap)
            val copiedAlias: JavaHashMap<String, Int> = JavaHashMap(javaMap)

            val kotlinMap: KotlinHashMap<String, Int> = asKotlinMap(javaMap)
            val backToJava: JavaHashMap<String, Int> = asJavaMap(kotlinMap)
            val mutableMap: MutableMap<String, Int> = backToJava

            val capacityOnly = HashMap<String, Int>(8)
            capacityOnly["capacity"] = 8

            val noImportKotlinMap: kotlin.collections.HashMap<String, Int> =
                kotlin.collections.HashMap()
            noImportKotlinMap["control"] = 7

            val erasedJava: Any = javaMap
            val erasedKotlin: Any = noImportKotlinMap

            println(capacityHashMap(8).size)
            println(copied == javaMap)
            println(copied["answer"])
            println(copiedAlias == javaMap)
            println(copiedAlias["answer"])
            println(kotlinMap === javaMap)
            println(backToJava === javaMap)
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

        for optLevel in [OptimizationLevel.O0, .O2] {
            try withTemporaryFile(contents: source) { input in
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .path
                defer { try? FileManager.default.removeItem(atPath: output + ".o") }

                let context = makeJavaUtilHashMapContext(
                    input: input,
                    output: output,
                    libraryPath: artifactPath,
                    emit: .object,
                    optLevel: optLevel
                )
                try runToKIR(context)
                try assertNoDiagnosticErrors(context)
                try LoweringPhase().run(context)
                try CodegenPhase().run(context)

                #expect(
                    FileManager.default.fileExists(atPath: output + ".o"),
                    "Expected an object file for fresh .kklib at \(optLevel)"
                )
            }
        }

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
                libraryPath: nil,
                emit: .executable,
                optLevel: .O0
            )
            try runToKIR(context)
            try assertNoDiagnosticErrors(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "source stdlib: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                "Unexpected source stdlib output"
            )
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
            moduleName: "KUU2234JavaUtilHashMap",
            inputs: [input],
            outputPath: output,
            emit: emit,
            target: defaultTargetTriple(),
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
