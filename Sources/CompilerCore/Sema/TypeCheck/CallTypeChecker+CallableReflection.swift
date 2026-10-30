extension CallTypeChecker {
    func inferCallableReferenceMember(
        _ id: ExprID, functionType: FunctionType, calleeName: InternedString,
        args: [CallArgument], safeCall: Bool, ctx: TypeInferenceContext, locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let fqName = ["kotlin", "reflect", "KCallable"].map(ctx.interner.intern) + [calleeName]
        guard let member = sema.symbols.lookup(fqName: fqName),
              let info = sema.symbols.symbol(member) else { return nil }
        let memberName = ctx.interner.resolve(calleeName)
        let resultType: TypeID
        if info.kind == .property, args.isEmpty, let type = sema.symbols.propertyType(for: member) {
            resultType = type
        } else if memberName == "callBy" {
            guard args.count == 1,
                  let signature = sema.symbols.functionSignature(for: member),
                  let expected = signature.parameterTypes.first,
                  let callRange = ctx.ast.arena.exprRange(id),
                  parameterMappingForCallArguments(args, in: signature, callRange: callRange, ctx: ctx) != nil
            else { return nil }
            let checkpoint = sema.diagnostics.checkpoint()
            var probeLocals = locals
            let argument = args[0].expr
            let argumentType = driver.inferExpr(argument, ctx: ctx, locals: &probeLocals, expectedType: expected)
            driver.emitSubtypeConstraint(
                left: argumentType,
                right: expected,
                range: ctx.ast.arena.exprRange(argument),
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: sema.diagnostics
            )
            if argumentType == sema.types.errorType
                || typeContainsErrorType(argumentType, sema: sema)
                || sema.diagnostics.diagnostics.dropFirst(checkpoint).contains(where: { $0.severity == .error })
            {
                // An inapplicable member must allow visible extensions to resolve.
                // Rebuild contextual bindings before ordinary argument preparation.
                sema.diagnostics.rollback(to: checkpoint)
                var restoredLocals = locals
                _ = driver.inferExpr(argument, ctx: ctx, locals: &restoredLocals)
                sema.diagnostics.rollback(to: checkpoint)
                return nil
            }
            locals = probeLocals
            resultType = functionType.returnType
        } else if memberName == "call" {
            for arg in args {
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
            }
            resultType = functionType.returnType
        } else { return nil }
        sema.bindings.bindIdentifier(id, symbol: member)
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }
}
