/// Resolves an explicit `LazyThreadSafetyMode` enum entry to the raw value
/// consumed by the runtime lazy factory. Dynamic mode expressions deliberately
/// fall back to the compiler-selected mode because they cannot be folded while
/// lowering a delegate declaration.
enum LazyThreadSafetyModeLowering {
    static func rawValue(
        from modeExpr: KIRExprID?,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        fallback: Int64
    ) -> Int64 {
        guard let modeExpr,
              case let .symbolRef(modeSymbol) = arena.expr(modeExpr),
              let symbol = sema.symbols.symbol(modeSymbol)
        else {
            return fallback
        }
        return rawValue(for: symbol.fqName.last, owner: Array(symbol.fqName.dropLast()), sema: sema, interner: interner)
            ?? fallback
    }

    static func rawValue(
        from delegateExpression: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        fallback: Int64
    ) -> Int64 {
        guard let delegateExpression,
              case let .call(_, _, arguments, _) = ast.arena.expr(delegateExpression)
        else {
            return fallback
        }

        for argument in arguments.dropLast().reversed() {
            guard let type = sema.bindings.exprTypes[argument.expr],
                  case let .classType(classType) = sema.types.kind(of: type),
                  let modeType = sema.symbols.symbol(classType.classSymbol),
                  modeType.fqName == [
                      interner.intern("kotlin"),
                      interner.intern("LazyThreadSafetyMode")
                  ],
                  case let .memberCall(_, memberName, _, _, _) = ast.arena.expr(argument.expr)
            else {
                continue
            }

            return rawValue(
                for: memberName,
                owner: modeType.fqName,
                sema: sema,
                interner: interner
            ) ?? fallback
        }
        return fallback
    }

    private static func rawValue(
        for memberName: InternedString?,
        owner: [InternedString],
        sema: SemaModule,
        interner: StringInterner
    ) -> Int64? {
        guard owner == [interner.intern("kotlin"), interner.intern("LazyThreadSafetyMode")],
              let memberName,
              let member = sema.symbols.lookupAll(fqName: owner + [memberName]).first,
              let symbol = sema.symbols.symbol(member)
        else {
            return nil
        }

        switch interner.resolve(symbol.name) {
        case "SYNCHRONIZED": return 1
        case "NONE": return 0
        case "PUBLICATION": return 2
        default: return nil
        }
    }
}
