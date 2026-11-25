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
