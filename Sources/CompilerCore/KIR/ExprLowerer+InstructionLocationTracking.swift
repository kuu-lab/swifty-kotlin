
extension ExprLowerer {
    func lowerExpr(
        _ exprID: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let beforeCount = instructions.instructions.count

        let exprRange = shared.ast.arena.exprRange(exprID)

        let result = lowerExpr(
            exprID,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )

        let afterCount = instructions.instructions.count
        while instructions.instructionLocations.count < beforeCount {
            instructions.instructionLocations.append(nil)
        }
        for _ in beforeCount ..< afterCount {
            instructions.instructionLocations.append(exprRange)
        }

        return result
    }
}
