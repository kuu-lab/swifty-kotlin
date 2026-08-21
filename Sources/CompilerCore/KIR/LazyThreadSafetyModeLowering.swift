/// Resolves explicit `LazyThreadSafetyMode` enum entries to the raw values
/// consumed by the runtime lazy factory. Non-constant mode expressions are
/// lowered as KIR values so runtime-selected modes are preserved; compiler
/// fallback is used only when the mode expression cannot be lowered as such.
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
              sema.symbols.symbol(modeSymbol) != nil
        else {
            return fallback
        }
        return constantRawValue(from: modeExpr, arena: arena, sema: sema, interner: interner)
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
              case .call = ast.arena.expr(delegateExpression)
        else {
            return fallback
        }

        return constantRawValue(
            from: delegateExpression,
            ast: ast,
            sema: sema,
            interner: interner
        ) ?? fallback
    }

    static func constantRawValue(
        from modeExpr: KIRExprID,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int64? {
        guard case let .symbolRef(modeSymbol) = arena.expr(modeExpr),
              let symbol = sema.symbols.symbol(modeSymbol)
        else {
            return nil
        }
        return rawValue(for: symbol, sema: sema, interner: interner)
    }

    static func constantRawValue(
        from delegateExpression: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int64? {
        guard let delegateExpression,
              case let .call(_, _, arguments, _) = ast.arena.expr(delegateExpression)
        else {
            return nil
        }
        for argument in arguments.dropLast().reversed() {
            guard let symbol = modeSymbol(
                for: argument.expr,
                ast: ast,
                sema: sema,
                interner: interner
            ) else {
                continue
            }
            return rawValue(for: symbol, sema: sema, interner: interner)
        }
        return nil
    }

    /// Returns the non-mode argument of a lazy factory call, if it is the
    /// explicit lock overload (`lazy(lock) { ... }`). A value typed as
    /// `LazyThreadSafetyMode` is deliberately not treated as a lock because
    /// the mode value is forwarded to the runtime lazy factory.
    static func lockExpression(
        from delegateExpression: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> ExprID? {
        guard let delegateExpression,
              case let .call(_, _, arguments, _) = ast.arena.expr(delegateExpression)
        else {
            return nil
        }
        for argument in arguments.dropLast().reversed() {
            guard let type = sema.bindings.exprTypes[argument.expr] else {
                return argument.expr
            }
            if isModeType(type, sema: sema, interner: interner) {
                continue
            }
            return argument.expr
        }
        return nil
    }

    /// KIR counterpart of `lockExpression`, used while lowering local
    /// delegated declarations whose factory arguments have already been
    /// lowered to KIR expressions.
    static func lockExpression(
        from arguments: [KIRExprID],
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner
    ) -> KIRExprID? {
        guard let candidate = arguments.dropLast().last else {
            return nil
        }
        guard let type = arena.exprType(candidate) else {
            return candidate
        }
        return isModeType(type, sema: sema, interner: interner) ? nil : candidate
    }

    private static func modeSymbol(
        for expression: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> SemanticSymbol? {
        guard let type = sema.bindings.exprTypes[expression],
              isModeType(type, sema: sema, interner: interner)
        else {
            return nil
        }

        if let symbol = sema.bindings.identifierSymbol(for: expression),
           sema.symbols.symbol(symbol) != nil
        {
            return sema.symbols.symbol(symbol)
        }

        guard case let .memberCall(_, memberName, _, _, _) = ast.arena.expr(expression),
              let member = sema.symbols.lookupAll(
                  fqName: [interner.intern("kotlin"), interner.intern("LazyThreadSafetyMode"), memberName]
              ).first
        else {
            return nil
        }
        return sema.symbols.symbol(member)
    }

    static func isModeType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let modeType = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return modeType.fqName == [interner.intern("kotlin"), interner.intern("LazyThreadSafetyMode")]
    }

    private static func rawValue(
        for symbol: SemanticSymbol,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int64? {
        rawValue(
            for: symbol.fqName.last,
            owner: Array(symbol.fqName.dropLast()),
            sema: sema,
            interner: interner
        )
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
