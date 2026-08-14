/// Binding for `String.chunked(size, transform)` and
/// `String.windowed(size, step, partialWindows, transform)` overloads: the
/// `List<R>`-returning counterparts of `chunkedSequence`/`windowedSequence`
/// source overloads. The sequence overloads are resolved directly from the
/// bundled declarations in `StringWindowChunkTransform.kt`.
///
/// The list transform overloads use uniquely named bundled functions rather
/// than declarations literally named `chunked`/`windowed`, because the KIR
/// lowering layer still has legacy by-name dispatch for those two names. The
/// resolved callee is identified by its real `declSite` and no external link
/// name.
///
/// Split out from `CallTypeChecker+MemberCallInference.swift`.
extension CallTypeChecker {
    func tryBindStringChunkedTransform(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard args.count == 2,
              interner.resolve(calleeName) == "chunked",
              isSyntheticStringLikeType(receiverType, sema: sema)
        else {
            return nil
        }
        guard let lambdaArgIndex = args.indices.first(where: { index in
            ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
        }) else {
            return nil
        }
        guard let sizeArgIndex = args.indices.first(where: { index in
            index != lambdaArgIndex
        }) else {
            return nil
        }
        guard explicitTypeArgs.count <= 1 else {
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            return sema.types.anyType
        }
        let charSequenceType = syntheticCharSequenceType(sema: sema) ?? sema.types.stringType
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: [charSequenceType],
            returnType: explicitTypeArgs.first ?? sema.types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(args[sizeArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        sema.bindings.markCollectionHOFLambdaExpr(args[lambdaArgIndex].expr)
        _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
        let bodyType = explicitTypeArgs.first
            ?? inferredLambdaReturnType(argExpr: args[lambdaArgIndex].expr, ast: ast, sema: sema)
        guard let chosen = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("kswiftkChunkedTransform"),
        ]).first(where: { candidate in
            isSourceBackedStringWindowChunkTransformCandidate(
                candidate,
                parameterCount: 2,
                sema: sema
            )
        }) else {
            return nil
        }
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [bodyType],
                parameterMapping: [sizeArgIndex: 0, lambdaArgIndex: 1]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let resultType = makeSyntheticListType(
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            elementType: bodyType
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func tryBindStringWindowedTransform(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard args.count == 4,
              interner.resolve(calleeName) == "windowed",
              isSyntheticStringLikeType(receiverType, sema: sema)
        else {
            return nil
        }
        guard let lambdaArgIndex = args.indices.first(where: { index in
            ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
        }) else {
            return nil
        }
        let scalarArgIndices = args.indices.filter { $0 != lambdaArgIndex }
        guard scalarArgIndices.count == 3 else {
            return nil
        }
        func scalarArgIndex(named name: String, fallbackPosition: Int) -> Int? {
            if let labeled = scalarArgIndices.first(where: { index in
                guard let label = args[index].label else { return false }
                return interner.resolve(label) == name
            }) {
                return labeled
            }
            guard fallbackPosition < scalarArgIndices.count else {
                return nil
            }
            return scalarArgIndices[fallbackPosition]
        }
        guard let sizeArgIndex = scalarArgIndex(named: "size", fallbackPosition: 0),
              let stepArgIndex = scalarArgIndex(named: "step", fallbackPosition: 1),
              let partialArgIndex = scalarArgIndex(named: "partialWindows", fallbackPosition: 2)
        else {
            return nil
        }
        guard explicitTypeArgs.count <= 1 else {
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            return sema.types.anyType
        }
        let charSequenceType = syntheticCharSequenceType(sema: sema) ?? sema.types.stringType
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: [charSequenceType],
            returnType: explicitTypeArgs.first ?? sema.types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(args[sizeArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        _ = driver.inferExpr(args[stepArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        _ = driver.inferExpr(args[partialArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
        sema.bindings.markCollectionHOFLambdaExpr(args[lambdaArgIndex].expr)
        _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
        let bodyType = explicitTypeArgs.first
            ?? inferredLambdaReturnType(argExpr: args[lambdaArgIndex].expr, ast: ast, sema: sema)
        guard let chosen = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("kswiftkWindowedTransform"),
        ]).first(where: { candidate in
            isSourceBackedStringWindowChunkTransformCandidate(
                candidate,
                parameterCount: 4,
                sema: sema
            )
        }) else {
            return nil
        }
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [bodyType],
                parameterMapping: [
                    sizeArgIndex: 0,
                    stepArgIndex: 1,
                    partialArgIndex: 2,
                    lambdaArgIndex: 3,
                ]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let resultType = makeSyntheticListType(
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            elementType: bodyType
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isSourceBackedStringWindowChunkTransformCandidate(
        _ candidate: SymbolID,
        parameterCount: Int,
        sema: SemaModule
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(candidate),
              symbol.kind == .function,
              sema.symbols.isSourceBackedSymbol(candidate),
              let signature = sema.symbols.functionSignature(for: candidate)
        else {
            return false
        }
        return signature.parameterTypes.count == parameterCount
    }
}
