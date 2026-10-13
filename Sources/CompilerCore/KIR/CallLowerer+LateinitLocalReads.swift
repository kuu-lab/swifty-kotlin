/// Receiver-function invocation can bypass the ordinary nameRef lowerer.
/// Keep its lateinit local read checked while preserving raw closure captures.
extension CallLowerer {
    func lowerLateinitLocalCallableRead(
        symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let info = sema.symbols.symbol(symbol),
              info.kind == .local, info.flags.contains(.lateinitProperty)
        else { return nil }
        let resultType = driver.ctx.localDeclaredType(for: symbol)
            ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
        let value: KIRExprID?
        if driver.ctx.isMutableCaptureBoxed(symbol) {
            value = driver.exprLowerer.loadMutableCaptureCellValue(
                symbol: symbol, resultType: resultType, sema: sema,
                arena: arena, interner: interner, instructions: &instructions
            )
        } else {
            value = driver.ctx.localValue(for: symbol)
        }
        guard let value else { return nil }
        return wrapLateinitReadIfNeeded(
            value, symbol: symbol, sema: sema, arena: arena,
            interner: interner, instructions: &instructions
        )
    }
}
