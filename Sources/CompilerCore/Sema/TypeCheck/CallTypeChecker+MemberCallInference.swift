
extension CallTypeChecker {
    func inferMemberCallImpl(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID {
        let request = MemberCallInferenceRequest(
            id: id,
            receiverID: receiverID,
            calleeName: calleeName,
            args: args,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall
        )

        markDeferredCollectionHOFLambdaIfNeeded(request)

        if let result = tryInferMemberCallWithoutReceiverSpecials(request, locals: &locals) {
            return result
        }

        if let result = tryInferFQNQualifiedValue(request, locals: locals) {
            return result
        }

        if let result = tryInferFQNPackageTopLevelCall(request, locals: &locals) {
            return result
        }

        var receiverType: TypeID
        if !safeCall, case let .nameRef(name, nameRange) = ctx.ast.arena.expr(receiverID) {
            receiverType = driver.exprChecker.inferNameRefExpr(
                receiverID, name: name, nameRange: nameRange, ctx: ctx,
                locals: &locals, isQualifier: true
            )
        } else {
            receiverType = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        }
        if !safeCall, receiverType != ctx.sema.types.errorType {
            receiverType = resolveSuperMemberReceiverType(
                receiverID: receiverID,
                receiverType: receiverType,
                calleeName: calleeName,
                ctx: ctx
            )
        }
        // The invalid super receiver already emitted its own diagnostic.
        // Resolving a member on the error type can introduce unrelated
        // extension candidates and produce a misleading overload error.
        if receiverType == ctx.sema.types.errorType,
           case .superRef = ctx.ast.arena.expr(receiverID)
        {
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
            return ctx.sema.types.errorType
        }
        if let result = tryInferMemberCallEarlyReceiverSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallScopeResultAndFileSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallCollectionFlowSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallStringRangeComparatorSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        return inferRegularMemberCall(request, receiverType: receiverType, locals: &locals)
    }

    private func resolveSuperMemberReceiverType(
        receiverID: ExprID,
        receiverType: TypeID,
        calleeName: InternedString,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard case let .superRef(nil, range) = ctx.ast.arena.expr(receiverID),
              let currentType = ctx.implicitReceiverType,
              case let .classType(currentClass) = sema.types.kind(of: currentType)
        else {
            return receiverType
        }

        var memberSupertypes: [TypeID] = []
        var concreteSupertypes: [TypeID] = []
        for superSymbol in sema.symbols.directSupertypes(for: currentClass.classSymbol) {
            let typeArgs = sema.types.liftedNominalSupertypeArgs(
                from: currentClass.classSymbol,
                childArgs: currentClass.args,
                to: superSymbol
            ) ?? []
            let superType = sema.types.make(.classType(ClassType(classSymbol: superSymbol, args: typeArgs)))
            // Supertype selection precedes overload applicability: even different
            // parameter lists require super<T> when both supertypes define the name.
            let members = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: superType,
                sema: sema,
                interner: ctx.interner
            )
            guard !members.isEmpty else { continue }
            memberSupertypes.append(superType)
            if members.contains(where: { sema.symbols.symbol($0)?.flags.contains(.abstractType) == false }) {
                concreteSupertypes.append(superType)
            }
        }

        let candidates = concreteSupertypes.isEmpty ? memberSupertypes : concreteSupertypes
        if candidates.count > 1 {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0056",
                "Multiple supertypes available. Specify the intended supertype in angle brackets, e.g. 'super<Foo>'.",
                range: range
            )
            sema.bindings.bindExprType(receiverID, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let selectedType = candidates.first else { return receiverType }
        sema.bindings.bindExprType(receiverID, type: selectedType)
        return selectedType
    }
}
