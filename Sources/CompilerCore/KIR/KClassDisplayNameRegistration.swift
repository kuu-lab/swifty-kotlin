/// Uses declaration ownership to separate package dots from nested-class separators.
private func kclassDisplayName(
    for symbolID: SymbolID, sema: SemaModule, interner: StringInterner
) -> String {
    guard let symbol = sema.symbols.symbol(symbolID) else { return "" }
    let parentID = sema.symbols.parentSymbol(for: symbolID)
        ?? sema.symbols.lookup(fqName: Array(symbol.fqName.dropLast()))
    if let parentID, let parent = sema.symbols.symbol(parentID) {
        switch parent.kind {
        case .class, .interface, .object, .enumClass, .annotationClass:
            return kclassDisplayName(for: parentID, sema: sema, interner: interner)
                + "$" + interner.resolve(symbol.name)
        default:
            break
        }
    }
    return symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
}

/// Called after metadata registration for literals and constructed nominal objects.
func emitKClassDisplayNameRegistration(
    symbol: SymbolID,
    typeTokenExpr: KIRExprID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    let name = interner.intern(kclassDisplayName(for: symbol, sema: sema, interner: interner))
    let nameExpr = arena.appendExpr(.stringLiteral(name), type: sema.types.intType)
    instructions.append(.constValue(result: nameExpr, value: .stringLiteral(name)))
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("__kk_kclass_register_display_name"),
        arguments: [typeTokenExpr, nameExpr],
        result: arena.appendTemporary(type: sema.types.intType),
        canThrow: false,
        thrownResult: nil
    ))
}
