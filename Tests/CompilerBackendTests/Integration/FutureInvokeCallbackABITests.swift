@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct FutureInvokeCallbackABITests {
    @Test(arguments: [0, 2])
    func callbacksUseRuntimeABI(optimization: Int) throws {
        let source = """
        @KsSymbolName("kk_future_invoke")
        external fun <T, R> invokeFuture(code: (T) -> R, value: T): R

        fun forwarded(code: (Int) -> Int, value: Int): Int = invokeFuture(code, value)

        fun main() {
            println(invokeFuture({ value: Int -> value + 1 }, 41))
            val offset = 7
            val code: (Int) -> Int = { it + offset }
            println(forwarded(code, 35))
            try {
                forwarded({ throw IllegalStateException("callback") }, 1)
            } catch (e: IllegalStateException) {
                println(e.message)
            }
        }
        """
        try withTemporaryFile(contents: source) { input in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "FutureInvokeABI", inputs: [input], outputPath: output,
                emit: .executable, target: .hostDefault(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: false, allowDefaultStdlibLibrary: false
            )))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "42\n42\ncallback\n")
        }
    }

    @Test
    func sourceStdlibO2IRPassesLLVMVerification() throws {
        let bindings = try #require(LLVMCAPIBindings.loadUsable())
        let verifier = try #require(bindings.verifyModuleFn)
        let source = try diffCaseSource("kclass_annotations_typed.kt", file: #filePath)
        try withTemporaryFile(contents: source) { input in
            let options = CompilerOptions(
                moduleName: "KUU1753", inputs: [input], outputPath: "unused",
                emit: .executable, target: .hostDefault(), optLevel: .O2,
                allowDefaultStdlibLibrary: false
            )
            let ctx = CompilationContext(
                options: options, sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try assertNoDiagnosticErrors(ctx)
            let emitter = NativeEmitter(
                target: options.target, optLevel: .O2, debugInfo: false,
                bindings: bindings, module: try #require(ctx.kir), interner: ctx.interner,
                moduleName: options.moduleName, typeSystem: ctx.sema?.types, symbols: ctx.sema?.symbols
            )
            let built = try emitter.buildModule()
            defer {
                bindings.disposeModule(built.module)
                for context in built.partitionContexts { bindings.disposeContext(context) }
                if built.ownsContext { bindings.disposeContext(built.context) }
            }
            var message: UnsafeMutablePointer<CChar>?
            defer { if let message { bindings.disposeMessageFn(message) } }
            let invalid = verifier(built.module, 2, &message)
            #expect(invalid == 0, "\(message.map { String(cString: $0) } ?? "LLVM verification failed")")
        }
    }
}
