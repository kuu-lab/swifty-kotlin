@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [false, true], [0, 2])
    func testMutexUndispatchedContinuation(useArtifact: Bool, optimization: Int) throws {
        let stdlib = useArtifact ? try Self.buildStdlibArtifact() : nil
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let cases = [
            ("mutex_undispatched_lock.kt", "release\nacquired\nfalse\n"),
            ("mutex_undispatched_owner.kt", "same owner\nrelease owner\ntrue\nwrong owner\nfalse\nfalse\n"),
            ("mutex_undispatched_cancel.kt", "cancelled waiter\nrelease after cancel\nnext waiter\nfalse\ncancelled owner waiter\nfalse\ntrue\ncancelled after handoff\nfalse\ncancelled fast path\ntrue\nfalse\n"),
            ("mutex_suspend_routing_controls.kt", "7\nfalse\n8\n1\n42\nclosed\n"),
        ]
        for (name, expected) in cases {
            let source = try diffCaseSource(name, file: #filePath)
            try withTemporaryFile(contents: source) { path in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let ctx = CompilationContext(options: CompilerOptions(
                    moduleName: "MutexContinuation", inputs: [path], outputPath: output,
                    emit: .executable, target: defaultTargetTriple(), optLevel: level,
                    includeStdlib: !useArtifact, stdlibLibraryPath: stdlib,
                    allowDefaultStdlibLibrary: false
                ), sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner())
                try runToLowering(ctx)
                try assertNoDiagnosticErrors(ctx)
                try CodegenPhase().run(ctx)
                try LinkPhase().run(ctx)
                let result = try CommandRunner.run(executable: output, arguments: [], timeout: 15)
                #expect(result.exitCode == 0, "\(name): stderr: \(result.stderr)")
                #expect(result.stdout == expected, "\(name), artifact=\(useArtifact), O\(optimization)")
            }
        }
    }

    @Test(arguments: [0, 2])
    func testMutexContinuationAcrossProducerLibrary(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try Self.buildStdlibArtifact()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let source = try diffCaseSource("mutex_undispatched_library.kt", file: #filePath)
        let split = try #require(source.range(of: "fun main()"))
        let producerSource = "package mutexfixture\n" + String(source[..<split.lowerBound])
        let consumerSource = "import kotlinx.coroutines.*\nimport kotlinx.coroutines.sync.*\nimport mutexfixture.*\n"
            + String(source[split.lowerBound...])
        let producerPath = directory.appendingPathComponent("Producer.kt").path
        let consumerPath = directory.appendingPathComponent("Consumer.kt").path
        let producerOutput = directory.appendingPathComponent("MutexProducer").path
        let output = directory.appendingPathComponent("consumer").path
        try producerSource.write(toFile: producerPath, atomically: true, encoding: .utf8)
        try consumerSource.write(toFile: consumerPath, atomically: true, encoding: .utf8)

        func context(path: String, module: String, output: String, emit: EmitMode,
                     libraries: [String] = []) -> CompilationContext {
            CompilationContext(options: CompilerOptions(
                moduleName: module, inputs: [path], outputPath: output, emit: emit,
                searchPaths: libraries, target: defaultTargetTriple(), optLevel: level,
                includeStdlib: false, stdlibLibraryPath: stdlib,
                allowDefaultStdlibLibrary: false
            ), sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner())
        }
        let producer = context(path: producerPath, module: "MutexProducer", output: producerOutput, emit: .library)
        try runToLowering(producer)
        try assertNoDiagnosticErrors(producer)
        try CodegenPhase().run(producer)
        let consumer = context(path: consumerPath, module: "MutexConsumer", output: output, emit: .executable,
                               libraries: [producerOutput + ".kklib"])
        try runToLowering(consumer)
        try assertNoDiagnosticErrors(consumer)
        try CodegenPhase().run(consumer)
        try LinkPhase().run(consumer)
        let result = try CommandRunner.run(executable: output, arguments: [], timeout: 15)
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout == "release library\nlibrary acquired\nfalse\nrelease owned library\ntrue\nfalse\n",
                "O\(optimization)")
    }
}
