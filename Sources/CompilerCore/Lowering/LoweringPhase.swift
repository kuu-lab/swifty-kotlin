
protocol LoweringPass: KIRPass {
    /// Stage that must hold before this pass is allowed to run.
    static var requiredStage: KIRStage { get }

    /// Stage established after this pass completes, whether it ran or was
    /// skipped because its feature gate returned false.
    static var producedStage: KIRStage { get }

    /// Returns `false` when the module contains no instructions that this
    /// pass would rewrite, allowing the driver to skip `run` entirely.
    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool
}

extension LoweringPass {
    func shouldRun(module _: KIRModule, ctx _: KIRContext) -> Bool {
        true
    }
}

/// Marker protocol for lowering passes whose `transformFunctions` closure
/// is safe for concurrent per-function execution.  The closure must not
/// mutate cross-function state — only `arena.appendExpr` (which is locked
/// when parallel mode is active) and per-function-local variables.
protocol ParallelLoweringPass: LoweringPass {}

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
            CoroutineLoweringPass(),
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
        // Imported inline bodies are materialized lazily: the inline pass
        // rebinds each body into this module's arena the first time a call
        // site expands to it (`ImportedInlineFunctionStore`).
        module.scanFeatures()
        // Parallel lowering is disabled: appendExpr assigns IDs under lock
        // in non-deterministic order, breaking KIR determinism tests.
        // ParallelLoweringPass conformance and KIRArena infrastructure are
        // kept for future enablement once per-function expression arenas
        // provide deterministic ID assignment.
        for pass in passes {
            let passType = type(of: pass)
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
