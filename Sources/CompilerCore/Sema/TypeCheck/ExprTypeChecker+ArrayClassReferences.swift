extension ExprTypeChecker {
    /// JVM class literals accept concrete Array types, while ordinary generic
    /// classifiers must omit their type arguments on the left of `::class`.
    func inferExplicitArrayClassRef(
        _ id: ExprID,
        receiverTypeRef: TypeRefID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        let target = driver.helpers.resolveTypeRef(
            receiverTypeRef, ast: ctx.ast, sema: sema, interner: ctx.interner,
            scope: ctx.scope, diagnostics: ctx.semaCtx.diagnostics,
            inferenceContext: ctx, usageRange: range
        )
        if target == sema.types.errorType {
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        guard let owner = resolveClassType(target, sema: sema),
              let symbol = sema.symbols.symbol(owner.classSymbol),
              symbol.fqName == [ctx.interner.intern("kotlin"), ctx.interner.intern("Array")],
              sema.types.nullability(of: target) == .nonNull,
              owner.args.count == 1,
              isConcreteClassLiteralType(target, arraySymbol: owner.classSymbol, sema: sema)
        else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Only concrete Array types may have type arguments on the left-hand side of '::class'.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        sema.bindings.bindClassRefTargetType(id, type: target)
        let result = sema.types.makeKClassType(argument: target)
        sema.bindings.bindExprType(id, type: result)
        return result
    }

    private func isConcreteClassLiteralType(_ type: TypeID, arraySymbol: SymbolID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: type) {
        case let .typeParam(parameter):
            return sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) == true
        case let .classType(owner):
            guard owner.classSymbol == arraySymbol else {
                return owner.args.isEmpty
            }
            guard owner.args.count == 1 else { return false }
            return owner.args.allSatisfy { argument in
                switch argument {
                case .star:
                    return false
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return isConcreteClassLiteralType(inner, arraySymbol: arraySymbol, sema: sema)
                }
            }
        case .primitive, .stringStruct, .any, .unit:
            return true
        default:
            return false
        }
    }
}
