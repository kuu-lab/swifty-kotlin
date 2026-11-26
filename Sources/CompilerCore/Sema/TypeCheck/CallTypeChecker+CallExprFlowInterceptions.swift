// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func inferFlowBuilderCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        let flowFactoryNames: Set<InternedString> = [
            knownNames.flow,
        ]
        if let calleeName,
           flowFactoryNames.contains(calleeName),
           args.count == 1,
           shouldUseBuiltinFlowFactorySpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            let flowLambdaExprID = args[0].expr
            guard isValidBuilderLambdaArgument(flowLambdaExprID, ast: ast) else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            var flowBuilderCtx = ctx.with(implicitReceiverType: sema.types.anyType)
            flowBuilderCtx.isFlowBuilderLambdaScope = true
            let flowInference = FlowBuilderInferenceSession(
                expectedElementType: resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs)
                    ?? flowBuilderElementType(expectedType, ctx: ctx),
                outerThisSymbol: locals[interner.intern("this")]?.symbol
            )
            flowBuilderCtx.flowBuilderInference = flowInference
            let flowLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.unitType,
                isSuspend: true,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                flowLambdaExprID,
                ctx: flowBuilderCtx,
                locals: &locals,
                expectedType: flowLambdaExpectedType
            )
            sema.bindings.markFlowExpr(id)
            let flowElementType = flowInference.elementType(types: sema.types)
            sema.bindings.bindFlowElementType(flowElementType, forExpr: id)
            let flowExprType = driver.helpers.makeFlowType(
                elementType: flowElementType, sema: sema, interner: interner
            ) ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: flowExprType)
            return flowExprType
        }
        return nil
    }

    func postponeFlowEmitAsConstraint(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        // During generic receiver-builder inference, postpone an unqualified
        // FlowCollector.emit argument as a constraint on the enclosing type
        // variables. The regular member-call path cannot resolve `R` until
        // these emissions have contributed evidence for it.
        // The final pass must bind the concrete collector member, including
        // when explicit type arguments supplied all inference evidence.
        if let builderInference = ctx.builderInference,
           !builderInference.isFinalized,
           let calleeName,
           calleeName == knownNames.emit,
           args.count == 1,
           locals[calleeName] == nil,
           let receiverType = ctx.implicitReceiverType,
           isFlowCollectorType(receiverType, ctx: ctx),
           let collectorType = resolveClassType(receiverType, sema: sema),
           let elementProjection = collectorType.args.first
        {
            let elementType: TypeID? = switch elementProjection {
            case let .invariant(type), let .in(type), let .out(type): type
            case .star: nil
            }
            if let elementType {
                let emittedType = driver.inferExpr(
                    args[0].expr, ctx: ctx, locals: &locals, expectedType: elementType
                )
                builderInference.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                    subtype: emittedType, supertype: elementType,
                    typeVarBySymbol: builderInference.typeVarBySymbol,
                    typeSystem: sema.types, blameRange: ast.arena.exprRange(args[0].expr)
                ).map { $0.withOrigin(.callArgument) })
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
        }
        return nil
    }

    func inferEmitInFlowScopeCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        if ctx.isFlowBuilderLambdaScope,
           let calleeName,
           calleeName == knownNames.emit,
           args.count == 1,
           locals[calleeName] == nil,
           !flowBuilderEmitHasReceiverMember(ctx: ctx, locals: locals)
        {
            let emittedType = driver.inferExpr(
                args[0].expr, ctx: ctx, locals: &locals,
                expectedType: ctx.flowBuilderInference?.expectedElementType
            )
            recordFlowBuilderEmission(emittedType, range: ast.arena.exprRange(args[0].expr), ctx: ctx)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }
        return nil
    }
}
