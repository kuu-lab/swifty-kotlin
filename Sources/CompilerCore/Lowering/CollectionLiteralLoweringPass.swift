final class CollectionLiteralLoweringPass: LoweringPass, ParallelLoweringPass {
    static let name = "CollectionLiteralLowering"
    static let requiredStage: KIRStage = .desugared
    static let producedStage: KIRStage = .desugared

    func run(module: KIRModule, ctx: KIRContext) throws {
        try CollectionLiteralLoweringRegistry(interner: ctx.interner)
            .run(module: module, ctx: ctx, recordAs: Self.name)
    }
}
