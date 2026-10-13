@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import RuntimeABI
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-1978: retain the original context consumer and exercise callbacks
    /// forwarded through delegation, source overrides, and imported bodies.
    @Test(arguments: [false, true], [0, 2])
    func testCoroutineContextFoldABI(useArtifact: Bool, optimization: Int) throws {
        let optLevel: OptimizationLevel = optimization == 0 ? .O0 : .O2
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cases = [
            (
                "coroutine_context_element_get",
                "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\nx\nz\ntrue\ntrue\nfalse\nfalse\ntrue\nfalse\n1\n2\nfalse\n1\ntrue\n1\nfalse\n2\ntrue\ntrue\nfalse\nfalse\n"
            ),
            (
                "coroutine_context_fold_delegation",
                "16\n16\n13\n13\n13\n13\n16\n12\ncaptured:3:10\nfold failure\n"
            ),
        ]
        let foldABI = try #require(RuntimeABISpec.byName["kk_context_fold"])
        #expect(foldABI.parameters.count == 5)
        #expect(foldABI.isThrowing)

        for (caseName, expectedOutput) in cases {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(
                "Scripts/diff_cases/\(caseName).kt"
            ), encoding: .utf8)
            try withTemporaryFile(contents: source) { inputPath in
                let outputBase = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputBase) }
                let context = CompilationContext(
                    options: CompilerOptions(
                        moduleName: "CoroutineContextFold",
                        inputs: [inputPath],
                        outputPath: outputBase,
                        emit: .executable,
                        target: defaultTargetTriple(),
                        optLevel: optLevel,
                        includeStdlib: !useArtifact,
                        stdlibLibraryPath: artifactPath,
                        allowDefaultStdlibLibrary: false
                    ),
                    sourceManager: SourceManager(),
                    diagnostics: DiagnosticEngine(),
                    interner: StringInterner()
                )
                try runToKIR(context)
                try assertNoDiagnosticErrors(context)
                try LoweringPhase().run(context)

                let module = try #require(context.kir)
                let sema = try #require(context.sema)
                var foldCallCount = 0
                for function in findAllKIRFunctions(in: module) {
                    for instruction in function.body {
                        guard case let .call(symbol, callee, arguments, _, canThrow, _, _, _) = instruction,
                              (symbol.flatMap { sema.symbols.externalLinkName(for: $0) }
                                ?? context.interner.resolve(callee)) == foldABI.name
                        else { continue }
                        foldCallCount += 1
                        // NativeEmitter appends outThrown to these four operands.
                        #expect(arguments.count == foldABI.parameters.count - 1)
                        #expect(canThrow)
                    }
                }
                #expect(foldCallCount > 0)

                do {
                    try CodegenPhase().run(context)
                    try LinkPhase().run(context)
                } catch {
                    throw TestCompilationFailure(description:
                        "\(caseName), artifact=\(useArtifact), O\(optimization): \(error); diagnostics: \(context.diagnostics.diagnostics)"
                    )
                }
                let result = try CommandRunner.run(executable: outputBase, arguments: [])
                #expect(result.exitCode == 0, "stderr: \(result.stderr)")
                #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expectedOutput)
            }
        }
    }
}
