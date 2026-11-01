extension ExprLowerer {
    func lowerCallableRefExpr(
        receiverExpr: ExprID?,
        memberName: InternedString,
        exprID: ExprID,
        boundType: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // When used as `T::class.simpleName`, the memberCall lowerer
        // intercepts and emits a direct kk_type_token_simple_name call
        // instead.  For standalone `T::class` (assigned to a variable,
        // passed as an argument, etc.) the KClass box is needed.
        if memberName == KnownCompilerNames(interner: interner).className,
           let classRefTargetType = sema.bindings.classRefTargetType(for: exprID)
        {
            let boundReceiver: KIRExprID?
            if sema.bindings.boundClassRefExprs.contains(exprID), let receiverExpr {
                let value = driver.lowerExpr(
                    receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                let boxed = arena.appendTemporary(type: sema.types.anyType)
                instructions.append(.copy(from: value, to: boxed))
                boundReceiver = boxed
            } else {
                boundReceiver = nil
            }
            let intType = sema.types.make(.primitive(.int, .nonNull))

            let tokenExpr: KIRExprID
            if boundReceiver == nil,
               case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
                if let capturedToken = driver.ctx.localValue(for: tokenSymbol) {
                    tokenExpr = capturedToken
                } else {
                    tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
                    instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
                }
            } else {
                let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
                tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
                instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
            }

            // kk_kclass_create ABI expects (Int, Int) — both parameters are
            // intptr_t.  The name hint is either a runtime string pointer
            // (passed as an int-typed string literal that codegen materialises
            // into a pointer bit-pattern) or 0 when no name is available.
            // We always use intType here to stay consistent with the ABI.
            let nameHintExpr: KIRExprID
            if let name = RuntimeTypeCheckToken.qualifiedName(of: classRefTargetType, sema: sema, interner: interner)
                ?? RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
                let internedName = interner.intern(name)
                nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: intType)
                instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
            } else {
                nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
            }

            // Prefer the sema-bound KClass<T> type and fall back to
            // KClass<classRefTargetType> so the result always carries the
            // precise generic parameter instead of degrading to Any.
            let kClassFallback = sema.types.makeKClassType(argument: classRefTargetType)
            let result = arena.appendTemporary(type: boundType ?? kClassFallback
            )
            // KUU-4018: `Array<E>::class` keys its KClass box on E's component
            // descriptor (JVM per-component array Class identity). Bound
            // `x::class` instead discovers the element from the value's
            // tagged component inside `__kk_kclass_of`.
            let arrayComponentExpr: KIRExprID?
            if boundReceiver == nil {
                arrayComponentExpr = driver.callLowerer.emitArrayKClassComponentExpr(
                    classRefTargetType: classRefTargetType,
                    sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                )
            } else {
                arrayComponentExpr = nil
            }
            let callee = boundReceiver == nil
                ? (arrayComponentExpr == nil ? "__kk_kclass_create" : "__kk_kclass_create_array")
                : "__kk_kclass_of"
            instructions.append(.call(
                callee: interner.intern(callee),
                arguments: (boundReceiver.map { [$0] } ?? []) + [tokenExpr, nameHintExpr]
                    + (arrayComponentExpr.map { [$0] } ?? []),
                result: result,
                canThrow: false
            ))

            // STDLIB-REFLECT-067: A standalone `T::class` box may later be
            // queried for metadata-backed members (e.g. `val k = Foo::class;
            // k.isData`). The member-call lowerer only registers metadata when
            // the receiver is a literal class-ref, so register it here too,
            // reusing the same `tokenExpr` so the box and its metadata share a
            // type token. No-op for reified type parameters / built-ins.
            driver.callLowerer.emitClassLiteralMetadataRegistration(
                classRefTargetType: classRefTargetType,
                typeTokenExpr: tokenExpr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return result
        }
        let value = driver.lambdaLowerer.lowerCallableRefExpr(
            exprID,
            receiverExpr: receiverExpr,
            memberName: memberName,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        return driver.callLowerer.materializeNominalFunctionValue(
            value,
            exprID: exprID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }
}
