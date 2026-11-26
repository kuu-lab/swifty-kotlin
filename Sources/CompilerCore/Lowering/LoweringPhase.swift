
protocol LoweringPass: KIRPass {
    static var requiredStage: KIRStage { get }

    static var producedStage: KIRStage { get }

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool
}

extension LoweringPass {
    func shouldRun(module _: KIRModule, ctx _: KIRContext) -> Bool {
        true
    }
}

public final class LoweringPhase: CompilerPhase {
    public static let name = "Lowerings"

    static func makeDefaultPasses() -> [any LoweringPass] {
        [
            TailrecLoweringPass(), // Must run before NormalizeBlocksPass (relies on beginBlock)
            NormalizeBlocksPass(),
            OperatorLoweringPass(),
            ForLoweringPass(),
            CollectionLiteralLoweringPass(),
            FlowLoweringPass(),
            IntroducedAtVersionOverloadingLoweringPass(),

            ValueClassUnboxingPass(), // VAL-001: must run before PropertyLowering
            PropertyLoweringPass(),
            JvmStaticLoweringPass(),
            JvmOverloadsLoweringPass(),
            DataEnumSealedSynthesisPass(),
            EnumEntriesLoweringPass(),
            ConsolePrintLoweringPass(),
            EnumNameAccessLoweringPass(),
            LambdaClosureConversionPass(),
            InlineLoweringPass(),
            ComposeLoweringPass(),
            ReifiedEnumValuesLoweringPass(),
            CoroutineLoweringPass(),
            TailrecAfterInlineLoweringPass(),
            // Must run after InlineLoweringPass so the `__kk_assertions_enabled`
            // guard inside expanded `kotlin.assert` bodies has materialized.
            AssertionsModeLoweringPass(),
            // Must run after every pass that emits integer arithmetic builtins
            // (Operator/For/Inline/...) and before ABILoweringPass so the inserted
            // narrowing calls participate in throw-channel resolution.
            IntegerNarrowingPass(),
            ABILoweringPass(),
        ]
    }

    private let passes: [any LoweringPass]

    public init() {
        self.passes = Self.makeDefaultPasses()
    }

    init(passes: [any LoweringPass]) {
        self.passes = passes
    }

    public func run(_ ctx: CompilationContext) throws {
        guard let module = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for lowering.")
        }
        let kirCtx = KIRContext(
            diagnostics: ctx.diagnostics,
            options: ctx.options,
            interner: ctx.interner,
            sema: ctx.sema
        )
        ctx.sema?.resolveDemandedImportedInlineBodies?(module)
        module.scanFeatures()
        let pluginPasses = CompilerPluginRegistry.plugins(for: ctx.options).flatMap(\.loweringPasses)
        // Parallel lowering is disabled: appendExpr assigns IDs under lock
        // in non-deterministic order, breaking KIR determinism tests.
        for pass in pluginPasses + passes {
            let passType = type(of: pass)
            try withSubPhaseTiming(passType.name, timer: ctx.phaseTimer) {
                try module.validateLoweringStage(
                    passName: passType.name,
                    required: passType.requiredStage,
                    produced: passType.producedStage
                )
                if pass.shouldRun(module: module, ctx: kirCtx) {
                    try pass.run(module: module, ctx: kirCtx)
                    // A pass that ran may have synthesized instructions the
                    // pre-pipeline scan never saw; drop the snapshot so the next
                    // `shouldRun` gate re-scans lazily instead of skipping on
                    // stale features (e.g. IntegerNarrowing after data-class
                    // hashCode synthesis in a module with no user arithmetic).
                    module.invalidateFeatureScan()
                } else {
                    module.recordLowering(type(of: pass).name)
                }
                module.advanceLoweringStage(to: passType.producedStage)
            }
        }
        if KIRVerifier.isEnabled {
            let failures = KIRVerifier.verify(
                module: module,
                symbols: ctx.sema?.symbols,
                interner: ctx.interner
            )
            for failure in failures.prefix(50) {
                ctx.diagnostics.error("KSWIFTK-KIR-0003", "KIR verifier: \(failure.message)", range: nil)
            }
        }
    }
}
