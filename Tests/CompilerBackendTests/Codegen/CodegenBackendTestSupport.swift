@testable import CompilerCore
@testable import CompilerBackend
import Foundation

final class CodegenBackendTestSupport {
    func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        emit: EmitMode,
        outputPath: String,
        irFlags: [String] = []
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: emit,
            target: defaultTargetTriple(),
            irFlags: irFlags
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        if emit == .kirDump {
            guard let kir = ctx.kir else {
                throw CompilerPipelineError.invalidInput("KIR not available for dump.")
            }
            let path = outputPath + ".kir"
            let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        } else {
            try CodegenPhase().run(ctx)
        }
        return ctx
    }
}
