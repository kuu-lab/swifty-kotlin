/// `-Xassertions=always-enable` / `always-disable` fix `kotlin.assert`'s
/// enablement at compile time (KUU-3817), mirroring kotlinc's assertions
/// modes. Calls to the `__kk_assertions_enabled` extern materialized in this
/// module's KIR — overwhelmingly the guard inside inlined `kotlin.assert`
/// bodies — fold to the configured constant. `always-disable` turns the
/// inlined body into an unconditional early return, so neither the condition
/// nor the lazy message evaluates (matching kotlinc, which erases the call
/// entirely); `always-enable` drops the guard so the check always runs.
/// `jvm`/`legacy` leave the extern call alone: the process environment decides
/// at startup (KUU-2751). State read by artifact-compiled functions
/// (`Class.desiredAssertionStatus`, `isAssertionThrowingErrorEnabled`) is
/// covered by the entry-wrapper override emitted from the same option.
final class AssertionsModeLoweringPass: LoweringPass {
    static let name = "AssertionsModeLowering"
    static let requiredStage: KIRStage = .propertyLowered
    static let producedStage: KIRStage = .propertyLowered

    private static let assertionsEnabledCallee = "__kk_assertions_enabled"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard ctx.options.assertionsMode.forcedState != nil else { return false }
        module.ensureFeaturesScanned()
        return module.usedCallees.contains(ctx.interner.intern(Self.assertionsEnabledCallee))
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let forcedState = ctx.options.assertionsMode.forcedState else {
            module.recordLowering(Self.name)
            return
        }
        let callee = ctx.interner.intern(Self.assertionsEnabledCallee)
        module.arena.transformFunctions { function in
            var updated = function
            var newBody = KIRLoweringEmitContext()
            newBody.instructions.reserveCapacity(function.body.count)
            for (index, instruction) in function.body.enumerated() {
                newBody.currentSourceRange = index < function.instructionLocations.count
                    ? function.instructionLocations[index]
                    : nil
                if case let .call(_, callCallee, _, result, _, _, _, _) = instruction,
                   callCallee == callee, let result {
                    newBody.append(.constValue(result: result, value: .boolLiteral(forcedState)))
                    continue
                }
                newBody.append(instruction)
            }
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }
}
