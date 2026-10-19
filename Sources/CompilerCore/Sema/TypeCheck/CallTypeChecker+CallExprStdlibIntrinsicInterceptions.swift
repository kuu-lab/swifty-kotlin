// swiftlint:disable file_length function_body_length cyclomatic_complexity

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
                let typeArg = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) ?? sema.types.anyType
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


        if let calleeName,
           let enumSpecialKind = enumStdlibSpecialCallKind(
               calleeName: calleeName,
               args: args,
               explicitTypeArgs: explicitTypeArgs,
               expectedType: expectedType,
               ctx: ctx,
               locals: locals,
               interner: interner,
               knownNames: knownNames,
               sema: sema,
               range: range
           )
        {
            switch enumSpecialKind {
            case let .enumValues(enumType, arrayType, stubSymbol):
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: [enumType],
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
        calleeName: InternedString?,
        calleePath: [InternedString]?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard args.count == 1,
              case .lambdaLiteral = ctx.ast.arena.expr(args[0].expr)
        else {
            return nil
        }

        let contractIntrinsicFQName = [
            interner.intern("kotlin"),
            interner.intern("contracts"),
            interner.intern("contract"),
        ]
        let candidates: [SymbolID]
        if calleePath == contractIntrinsicFQName {
            candidates = sema.symbols.lookupAll(fqName: contractIntrinsicFQName)
        } else if let calleeName, locals[calleeName] == nil {
            candidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        } else {
            return nil
        }
        guard let intrinsic = candidates.first(where: {
            sema.wellKnownSymbols.isContractIntrinsic(for: $0)
        }),
              let signature = sema.symbols.functionSignature(for: intrinsic),
              signature.parameterTypes.count == 1,
              case let .functionType(lambdaType) = sema.types.kind(of: signature.parameterTypes[0]),
              let builderType = lambdaType.receiver
        else {
            return nil
        }

        // A same-named overload that accepts a function or SAM value must go
        // through ordinary overload resolution. This keeps the special path
        // tied to the selected stdlib declaration when lambda calls overlap.
        let hasCallableUserOverload = candidates.contains { candidate in
            guard !sema.wellKnownSymbols.isContractIntrinsic(for: candidate),
                  let candidateSignature = sema.symbols.functionSignature(for: candidate),
                  candidateSignature.parameterTypes.count == 1
            else {
                return false
            }
            let parameterType = candidateSignature.parameterTypes[0]
            if case .functionType = sema.types.kind(of: parameterType) {
                return true
            }
            return driver.helpers.samFunctionType(for: parameterType, sema: sema) != nil
                || sema.types.typeContainsAnyTypeParam(parameterType)
        }
        guard !hasCallableUserOverload else { return nil }

        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx.with(implicitReceiverType: builderType),
            locals: &locals,
            expectedType: signature.parameterTypes[0]
        )
        // The body is compiler-only, but record the exact declaration that
        // selected this path so later consumers cannot confuse a user overload.
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: intrinsic,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(intrinsic))
        sema.bindings.markStdlibSpecialCallExpr(id, kind: .contract)
        sema.bindings.bindExprType(id, type: signature.returnType)
        return signature.returnType
    }

}
