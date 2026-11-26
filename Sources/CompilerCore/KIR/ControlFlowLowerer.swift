
final class ControlFlowLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func isTerminatedExpr(_ exprID: KIRExprID, arena: KIRArena, sema: SemaModule) -> Bool {
        arena.exprType(exprID) == sema.types.nothingType
    }
}
