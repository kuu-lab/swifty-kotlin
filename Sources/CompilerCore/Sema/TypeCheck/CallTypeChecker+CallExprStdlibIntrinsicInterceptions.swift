// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Stdlib intrinsic call interceptions from the `inferCallExpr` dispatch
/// chain: `kotlin.reflect.typeOf`, the `enumValues`/`enumValueOf`/`values`/
/// `valueOf`/`entries` enum specials, and `contract { }`.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    func inferReflectTypeOfCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        calleePath: [InternedString]?,
        locals: LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        // --- STDLIB-REFLECT-066: typeOf<T>() — inline reified reflection ---
        let typeOfIntrinsicFQName = [
            interner.intern("kotlin"), interner.intern("reflect"), interner.intern("typeOf"),
        ]
        let isQualifiedReflectTypeOf = calleePath == typeOfIntrinsicFQName
        let isUnqualifiedTypeOf = calleeName.map {
            $0 == knownNames.typeOf && locals[$0] == nil
        } ?? false
        if args.isEmpty, isQualifiedReflectTypeOf || isUnqualifiedTypeOf {
            // KSP-1323: the bundled kotlin.reflect.typeOf declaration is the
            // intrinsic owner. A same-named non-synthetic user declaration
            // still shadows the unqualified special-call path, but the bundled
            // intrinsic itself no longer counts as shadowing. The qualified
            // `kotlin.reflect.typeOf` spelling cannot be shadowed.
            let typeOfName = interner.intern("typeOf")
            let hasNonSyntheticUserCandidate = isUnqualifiedTypeOf
                && !isQualifiedReflectTypeOf
                && ctx.cachedScopeLookup(typeOfName).contains { candidate in
                    guard let sym = ctx.cachedSymbol(candidate),
                          !sym.flags.contains(.synthetic)
                    else { return false }
                    return sema.wellKnownSymbols.reflectIntrinsic(for: candidate) == nil
                }
            let candidates = ctx.filterByVisibility(ctx.cachedScopeLookup(typeOfName)).visible
            if !hasNonSyntheticUserCandidate,
               let stubSymbol = candidates.first(where: { candidate in
                   sema.wellKnownSymbols.reflectIntrinsic(for: candidate) == .typeOf
               }) ?? candidates.first(where: { candidate in
                   guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                   return signature.reifiedTypeParameterIndices.contains(0)
               }), let signature = sema.symbols.functionSignature(for: stubSymbol) {
                let typeArg = explicitTypeArgs.first ?? sema.types.anyType
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: [typeArg],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .typeOf)
                sema.bindings.bindExprType(id, type: signature.returnType)
                return signature.returnType
            }
        }
        return nil
    }

    func inferEnumStdlibSpecialCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        // --- Stdlib enumValues<T>() / enumValueOf<T>(name) (STDLIB-171) ---
        if let calleeName,
           let enumSpecialKind = enumStdlibSpecialCallKind(
               calleeName: calleeName,
               args: args,
               explicitTypeArgs: explicitTypeArgs,
               ctx: ctx,
               locals: locals,
               interner: interner,
               knownNames: knownNames,
               sema: sema,
               range: range
           )
        {
            switch enumSpecialKind {
            case let .enumValues(_, arrayType, stubSymbol):
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValues)
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: arrayType)
                return arrayType
            case let .enumValueOf(enumType, stubSymbol):
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValueOf)
                sema.bindings.bindExprType(id, type: enumType)
                return enumType
            case let .enumEntries(enumType, entriesType, stubSymbol):
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: [enumType],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumEntries)
                sema.bindings.bindExprType(id, type: entriesType)
                return entriesType
            }
        }
        return nil
    }

    func inferContractCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        calleeName: InternedString?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        if let calleeName,
           calleeName == knownNames.contract,
           args.count == 1
        {
            let builderSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("contracts"),
                interner.intern("ContractBuilder"),
            ])
            let builderType = builderSymbol.map {
                sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
            } ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: builderType,
                params: [],
                returnType: sema.types.unitType
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx.with(implicitReceiverType: builderType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            // Contract effects are consumed by Sema and have no runtime
            // representation. Mark the call so KIR does not lower its builder
            // lambda, whose effect expressions may otherwise become runtime
            // calls even though the contract itself is compiler-only.
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .contract)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }
        return nil
    }
}
