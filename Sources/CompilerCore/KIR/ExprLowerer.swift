
final class ExprLowerer {
    unowned let driver: KIRLoweringDriver
    private var lambdaCapturedSymbols: Set<SymbolID>?

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func isCapturedByLambda(_ symbol: SymbolID, sema: SemaModule) -> Bool {
        // Sema has completed before this lowering session starts. Cache its
        // capture union once instead of rescanning every lambda for each local.
        // `localFunctionCaptureSymbolsBySymbol` must join the union too: a
        // `var` captured only by a local/anonymous function (its captures are
        // keyed by the function *symbol*, not a lambda ExprID) still needs its
        // cell to dominate every use — otherwise a capture created inside a
        // loop body boxes the variable after the loop condition already read
        // the unboxed register, and mutations never reach it (KUU-4120).
        if lambdaCapturedSymbols == nil {
            var captured = Set(sema.bindings.captureSymbolsByExpr.values.joined())
            captured.formUnion(sema.bindings.localFunctionCaptureSymbolsBySymbol.values.joined())
            // Object literals and local nominals keep captures in a third
            // table keyed by the owner nominal; their members lazily box a
            // captured `var` at the construction site the same way.
            captured.formUnion(sema.bindings.objectLiteralCaptureSymbolsByOwner.values.joined())
            lambdaCapturedSymbols = captured
        }
        return lambdaCapturedSymbols?.contains(symbol) == true
    }
}
