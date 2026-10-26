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

private func localKClassCastName(
    for symbolID: SymbolID,
    symbol: SemanticSymbol,
    sema: SemaModule,
    interner: StringInterner
) -> String? {
    let components = symbol.fqName.map { interner.resolve($0) }
    let isAnonymousObject = components.contains { $0.hasPrefix("__ObjectLiteral_") }
    guard isAnonymousObject || components.contains(where: { $0.hasPrefix("__localdecl_") }),
          let declarationRange = symbol.declSite
    else {
        return nil
    }

    let symbols = sema.symbols.allSymbols()
    let enclosingCallables = symbols.filter { candidate in
        guard candidate.kind == .function || candidate.kind == .constructor,
              candidate.id != symbolID,
              sema.symbols.parentSymbol(for: candidate.id) != symbolID,
              let candidateRange = candidate.declSite
        else {
            return false
        }
        return candidateRange.contains(declarationRange)
    }
    let enclosingCallable = enclosingCallables.min { lhs, rhs in
        guard let lhsRange = lhs.declSite, let rhsRange = rhs.declSite else { return false }
        let lhsLength = lhsRange.end.offset - lhsRange.start.offset
        let rhsLength = rhsRange.end.offset - rhsRange.start.offset
        return lhsLength == rhsLength ? lhs.id.rawValue < rhs.id.rawValue : lhsLength < rhsLength
    }
    guard let enclosingCallable else { return nil }

    let ownerName = enclosingCallable.fqName.map { interner.resolve($0) }.joined(separator: ".")
    guard !ownerName.isEmpty else { return nil }

    let localName: String
    if isAnonymousObject {
        let ownerRange = enclosingCallable.declSite!
        let anonymousSiblings = symbols.filter { candidate in
            guard candidate.id != symbolID,
                  candidate.fqName.contains(where: { interner.resolve($0).hasPrefix("__ObjectLiteral_") }),
                  let candidateRange = candidate.declSite
            else {
                return false
            }
            return ownerRange.contains(candidateRange)
                && candidateRange.start.file == declarationRange.start.file
        }
        let precedingCount = anonymousSiblings.filter { candidate in
            guard let candidateRange = candidate.declSite else { return false }
            return candidateRange.start.offset < declarationRange.start.offset
        }.count
        localName = String(precedingCount + 1)
    } else {
        localName = interner.resolve(symbol.name)
    }
    return "\(ownerName)$\(localName)"
}

func emitKClassCastNameRegistration(
    symbol: SymbolID,
    typeTokenExpr: KIRExprID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    guard let classInfo = sema.symbols.symbol(symbol),
          let castName = localKClassCastName(
              for: symbol, symbol: classInfo, sema: sema, interner: interner
          )
    else {
        return
    }
    let name = interner.intern(castName)
    let nameExpr = arena.appendExpr(.stringLiteral(name), type: sema.types.intType)
    instructions.append(.constValue(result: nameExpr, value: .stringLiteral(name)))
    instructions.append(.call(
        callee: interner.intern("__kk_kclass_register_cast_name"),
        arguments: [typeTokenExpr, nameExpr],
        result: arena.appendTemporary(type: sema.types.intType),
        canThrow: false
    ))
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
        callee: interner.intern("__kk_kclass_register_display_name"),
        arguments: [typeTokenExpr, nameExpr],
        result: arena.appendTemporary(type: sema.types.intType),
        canThrow: false
    ))
}
