extension CallTypeChecker {
    func inferCallableReferenceMember(
        _ id: ExprID, receiverID: ExprID, functionType: FunctionType, calleeName: InternedString,
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
        } else if memberName == "call" || memberName == "callBy" {
            if memberName == "callBy", args.count != 1 { return nil }
            for arg in args {
                let expected = memberName == "callBy" ? sema.symbols.functionSignature(for: member)?.parameterTypes.first : nil
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: expected)
            }
            resultType = functionType.returnType
        } else { return nil }
        sema.bindings.bindIdentifier(id, symbol: member)
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }
}
