#if canImport(Testing)
@testable import CompilerCore
import Testing

struct KIRStageTests {
    @Test
    func testDefaultLoweringPassesDeclareAnOrderedStagePipeline() {
        var stage: KIRStage = .raw

        for pass in LoweringPhase.makeDefaultPasses() {
            let passType = type(of: pass)
            #expect(
                passType.requiredStage == stage,
                "\(passType.name) requires \(passType.requiredStage), current stage is \(stage)"
            )
            #expect(
                passType.producedStage >= passType.requiredStage,
                "\(passType.name) regresses from \(passType.requiredStage) to \(passType.producedStage)"
            )
            stage = passType.producedStage
        }

        #expect(stage == .abiLowered)
    }

    @Test
    func testLoweringPhasePublishesABILoweredStageAfterSuccessfulRun() throws {
        let module = KIRModule(files: [], arena: KIRArena())
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "KIRStage",
            includeStdlib: false
        )
        ctx.kir = module

        try LoweringPhase().run(ctx)

        #expect(module.stage == .abiLowered)
    }

    #if DEBUG
    @Test
    func testLoweringPhaseRejectsAnOutOfOrderPassBeforeRunningIt() {
        let module = KIRModule(files: [], arena: KIRArena())
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "KIRStageViolation",
            includeStdlib: false
        )
        ctx.kir = module

        let incorrectlyOrderedPhase = LoweringPhase(passes: [
            TailrecLoweringPass(),
            NormalizeBlocksPass(),
            TailrecLoweringPass(),
        ])

        #expect(throws: KIRStageViolation.self) {
            try incorrectlyOrderedPhase.run(ctx)
        }
        #expect(module.stage == .desugared)
        #expect(module.executedLowerings == [
            TailrecLoweringPass.name,
            NormalizeBlocksPass.name,
        ])
    }
    #endif
}
#endif
