#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Runs only `CollectionLiteralLoweringPass`, so a failure names that pass
/// rather than some later rewrite in `LoweringPhase`.
func runCollectionLiteralPassOnly(_ ctx: CompilationContext) throws -> KIRModule {
    let module = try #require(ctx.kir)
    let kirCtx = KIRContext(
        diagnostics: ctx.diagnostics,
        options: ctx.options,
        interner: ctx.interner,
        sema: ctx.sema
    )
    module.scanFeatures()
    try CollectionLiteralLoweringPass().run(module: module, ctx: kirCtx)
    return module
}
#endif
