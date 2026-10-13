@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2033: compile the exact producer before consuming its captured tokens.
    @Test(arguments: [false, true], [0, 2])
    func testReifiedEnumValuesEscapingLambda(useArtifact: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = useArtifact ? try Self.buildStdlibArtifact() : nil
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let source = try diffCaseSource("enum_values_reified_escaping_lambda.kt", file: #filePath)
        let split = try #require(source.range(of: "enum class E"))
        let producerSource = String(source[..<split.lowerBound])
        let consumerSource = "package app\nimport fixture.*\n" + String(source[split.lowerBound...])
        let producerPath = directory.appendingPathComponent("Factory.kt").path
        let producerOutput = directory.appendingPathComponent("ReifiedCapture").path
        try producerSource.write(toFile: producerPath, atomically: true, encoding: .utf8)

        func context(inputs: [String], moduleName: String, emit: EmitMode, output: String,
                     libraries: [String] = []) -> CompilationContext {
            CompilationContext(
                options: CompilerOptions(
                    moduleName: moduleName, inputs: inputs, outputPath: output, emit: emit,
                    searchPaths: libraries, target: defaultTargetTriple(), optLevel: optLevel,
                    includeStdlib: !useArtifact, stdlibLibraryPath: stdlib,
                    allowDefaultStdlibLibrary: false
                ),
                sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
        }

        let producer = context(inputs: [producerPath], moduleName: "ReifiedCapture", emit: .library,
                               output: producerOutput)
        try runToLowering(producer)
        try assertNoDiagnosticErrors(producer)
        // The escaping body must use the runtime token; its enum is chosen by the consumer.
        let module = try #require(producer.kir)
        #expect(findAllKIRFunctions(in: module).contains { function in
            function.body.contains { instruction in
                guard case let .call(nil, callee, _, _, _, _, _, _) = instruction else { return false }
                return producer.interner.resolve(callee) == "kk_enum_values_for_token"
            }
        })
        try CodegenPhase().run(producer)
        #expect(FileManager.default.fileExists(atPath: producerOutput + ".kklib/manifest.json"))

        for importedProducer in [false, true] {
            let path = directory.appendingPathComponent(importedProducer ? "Consumer.kt" : "Source.kt").path
            try (importedProducer ? consumerSource : source).write(toFile: path, atomically: true, encoding: .utf8)
            let output = directory.appendingPathComponent(importedProducer ? "consumer" : "source").path
            let consumer = context(
                inputs: [path], moduleName: "ReifiedCaptureConsumer", emit: .executable, output: output,
                libraries: importedProducer ? [producerOutput + ".kklib"] : []
            )
            try runToLowering(consumer)
            try assertNoDiagnosticErrors(consumer)
            try CodegenPhase().run(consumer)
            try LinkPhase().run(consumer)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout == "[A, B]\n[X, Y, Z]\nA\n0\n[A, B]\ncount:3\n[mapped:2]\n[A, B]\n",
                    "artifact=\(useArtifact), O\(optimization), importedProducer=\(importedProducer)")
        }
    }
}
