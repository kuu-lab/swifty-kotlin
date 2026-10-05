
/// Returns a canonical string key for a when-branch condition expression,
/// used for detecting duplicate conditions (Sema) and deduplicating
/// OR-chain comparisons (KIR).  Returns `nil` for conditions that
/// cannot be reliably compared (e.g. arbitrary expressions).
func whenConditionKey(
    for conditionID: ExprID,
    ast: ASTModule,
    sema: SemaModule,
    interner: StringInterner
) -> String? {
    guard let expr = ast.arena.expr(conditionID) else {
        return nil
    }
    return whenConditionKeyFromExpr(
        expr,
        conditionID: conditionID,
        ast: ast,
        sema: sema,
        interner: interner
    )
}

/// Computes a canonical key from an already-resolved expression node.
/// Split out to keep the switch statement in its own function so that
/// the top-level helper stays below the cyclomatic-complexity threshold.
private func whenConditionKeyFromExpr(
    _ expr: Expr,
    conditionID: ExprID,
    ast: ASTModule,
    sema: SemaModule,
    interner: StringInterner
) -> String? {
    if let literalKey = literalConditionKey(expr, interner: interner) {
        return literalKey
    }
    switch expr {
    case let .nameRef(name, _):
        return nameRefKey(name: name, conditionID: conditionID, sema: sema, interner: interner)
    case let .memberCall(receiver, _, _, args, _):
        return memberCallKey(
            receiver: receiver, args: args,
            conditionID: conditionID, ast: ast, sema: sema, interner: interner
        )
    case let .isCheck(_, typeRefID, negated, _):
        return isCheckKey(typeRefID: typeRefID, negated: negated, conditionID: conditionID, sema: sema)
    default:
        return nil
    }
}

/// Returns a canonical key for literal expression types, or `nil` if
/// the expression is not a literal.
private func literalConditionKey(_ expr: Expr, interner: StringInterner) -> String? {
    switch expr {
    case let .intLiteral(value, _): "int:\(value)"
    case let .longLiteral(value, _): "long:\(value)"
    case let .uintLiteral(value, _): "uint:\(value)"
    case let .ulongLiteral(value, _): "ulong:\(value)"
    case let .doubleLiteral(value, _): "double:\(value)"
    case let .floatLiteral(value, _): "float:\(value)"
    case let .charLiteral(value, _): "char:\(value)"
    case let .boolLiteral(value, _): "bool:\(value)"
    case let .stringLiteral(value, _): "string:\(interner.resolve(value))"
    default: nil
    }
}

private func nameRefKey(
    name: InternedString,
    conditionID: ExprID,
    sema: SemaModule,
    interner: StringInterner
) -> String? {
    let resolved = interner.resolve(name)
    if resolved == "null" {
        return "null"
    }
    if let symbolID = sema.bindings.identifierSymbols[conditionID] {
        return "sym:\(symbolID.rawValue)"
    }
    return "name:\(resolved)"
}

private func memberCallKey(
    receiver: ExprID,
    args: [CallArgument],
    conditionID: ExprID,
    ast: ASTModule,
    sema: SemaModule,
    interner: StringInterner
) -> String? {
    guard args.isEmpty,
          !ast.arena.isExplicitCall(conditionID),
          let symbolID = sema.bindings.identifierSymbols[conditionID],
          let symbol = sema.symbols.symbol(symbolID)
    else {
        return nil
    }
    let symbolKey = "sym:\(symbolID.rawValue)"
    switch symbol.kind {
    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
        return symbolKey
    case .property, .field:
        // Enum entries and constants identify values independently of their qualifier.
        if symbol.flags.contains(.constValue)
            || (symbol.kind == .field
                && sema.symbols.lookupAll(fqName: Array(symbol.fqName.dropLast())).contains {
                    sema.symbols.symbol($0)?.kind == .enumClass
                })
        {
            return symbolKey
        }
        guard let receiverKey = whenConditionKey(for: receiver, ast: ast, sema: sema, interner: interner) else {
            return nil
        }
        return "member:\(receiverKey).\(symbolKey)"
    default:
        return nil
    }
}

private func isCheckKey(
    typeRefID: TypeRefID,
    negated: Bool,
    conditionID: ExprID,
    sema: SemaModule
) -> String? {
    if let targetType = sema.bindings.isCheckTargetType(for: conditionID) {
        return "is:\(negated ? "!" : "")\(targetType.rawValue)"
    }
    return "is:\(negated ? "!" : "")\(typeRefID.rawValue)"
}

/// Removes duplicate conditions from a when-branch condition list,
/// keeping the first occurrence of each canonically-equal condition.
func deduplicateWhenConditions(
    _ conditions: [ExprID],
    ast: ASTModule,
    sema: SemaModule,
    interner: StringInterner
) -> [ExprID] {
    var seen: Set<String> = []
    var result: [ExprID] = []
    for cond in conditions {
        if let key = whenConditionKey(for: cond, ast: ast, sema: sema, interner: interner) {
            if seen.insert(key).inserted {
                result.append(cond)
            }
        } else {
            // Cannot compute a canonical key — keep the condition to be safe.
            result.append(cond)
        }
    }
    return result
}
