#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LoweringABIAndPropertyRegressionTests {
    @discardableResult
    func runLowering(
        module: KIRModule,
        interner: StringInterner,
        moduleName: String,
        emit: EmitMode = .kirDump,
        sema: SemaModule? = nil,
        diagnostics: DiagnosticEngine = DiagnosticEngine()
    ) throws -> CompilationContext {
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: moduleName,
            emit: emit,
            interner: interner,
            diagnostics: diagnostics
        )
        ctx.kir = module
        ctx.sema = sema
        try LoweringPhase().run(ctx)
        return ctx
    }
}
#endif
