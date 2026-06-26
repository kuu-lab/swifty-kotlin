
extension CallTypeChecker {
    struct MemberCallInferenceRequest {
        let id: ExprID
        let receiverID: ExprID
        let calleeName: InternedString
        let args: [CallArgument]
        let range: SourceRange
        let ctx: TypeInferenceContext
        let expectedType: TypeID?
        let explicitTypeArgs: [TypeID]
        let safeCall: Bool
    }

    func markDeferredCollectionHOFLambdaIfNeeded(_ request: MemberCallInferenceRequest) {
        let ast = request.ctx.ast
        let sema = request.ctx.sema
        let interner = request.ctx.interner
        let calleeName = request.calleeName
        let args = request.args

        if ["firstNotNullOf", "firstNotNullOfOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "reduceRightOrNull", "sumBy", "sumByDouble", "takeLastWhile"]
            .contains(interner.resolve(calleeName)),
            args.count == 1,
            let lambdaExpr = ast.arena.expr(args[0].expr),
            lambdaExpr.isLambdaOrCallableRef
        {
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        }
    }

    func tryInferMemberCallWithoutReceiverSpecials(
        _ request: MemberCallInferenceRequest,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let explicitTypeArgs = request.explicitTypeArgs

        if let result = tryInferLateinitIsInitializedCall(
            id, receiverID: receiverID, calleeName: calleeName, args: args,
            range: range, ctx: ctx, locals: &locals
        ) {
            return result
        }

        if let result = tryInferClassRefMemberCall(
            id, receiverID: receiverID, calleeName: calleeName, args: args,
            explicitTypeArgs: explicitTypeArgs, range: range, ctx: ctx, locals: &locals
        ) {
            return result
        }

        if let result = tryInferNumericCompanionMemberCall(
            id, receiverID: receiverID, calleeName: calleeName, args: args,
            ctx: ctx, locals: &locals
        ) {
            return result
        }

        return nil
    }

    /// FQN package-qualified top-level function call: e.g. kotlin.math.abs(x).
    /// Fires before receiver inference to avoid SEMA-0022 on unresolvable package identifiers.
    func tryInferFQNPackageTopLevelCall(
        _ request: MemberCallInferenceRequest,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let explicitTypeArgs = request.explicitTypeArgs
        let sema = ctx.sema
        let ast = ctx.ast

        guard let receiverPath = qualifiedCalleePath(for: receiverID, ast: ast),
              !receiverPath.isEmpty,
              locals[receiverPath[0]] == nil
        else { return nil }

        let fqnPath = receiverPath + [calleeName]
        let fqnCandidates = sema.symbols.lookupAll(fqName: fqnPath).filter { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else { return false }
            return symbol.kind == .function || symbol.kind == .constructor
        }
        guard !fqnCandidates.isEmpty else { return nil }

        let (vis, _) = ctx.filterByVisibility(fqnCandidates)
        guard !vis.isEmpty else { return nil }

        let argTypes = args.map { arg -> TypeID in
            sema.bindings.exprType(for: arg.expr) ?? driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
        }
        let callArgs = zip(args, argTypes).map { arg, type in
            CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
        }
        let call = CallExpr(
            range: range,
            calleeName: calleeName,
            args: callArgs,
            explicitTypeArgs: explicitTypeArgs
        )
        let resolved = ctx.resolver.resolveCall(
            candidates: vis,
            call: call,
            expectedType: request.expectedType,
            ctx: sema
        )
        guard let chosen = resolved.chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosen)
        else { return nil }

        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let resultType = sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    func recoveredMemberCallReceiverType(
        receiverID: ExprID,
        receiverType: TypeID,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        if case .any = sema.types.kind(of: sema.types.makeNonNullable(receiverType)) {
            if let symbol = sema.bindings.identifierSymbol(for: receiverID),
               let propertyType = sema.symbols.propertyType(for: symbol)
            {
                return propertyType
            } else if case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
                      let local = locals[receiverName]
            {
                return sema.symbols.propertyType(for: local.symbol) ?? local.type
            }
        }
        return nil
    }
}
