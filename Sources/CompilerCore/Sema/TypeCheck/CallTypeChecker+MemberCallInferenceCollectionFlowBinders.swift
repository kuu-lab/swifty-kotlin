// swiftlint:disable file_length function_body_length cyclomatic_complexity

private func typeArgumentsMatch(
    _ lhs: TypeArg,
    _ rhs: TypeArg,
    using typeMatches: (TypeID, TypeID) -> Bool
) -> Bool {
    switch (lhs, rhs) {
    case let (.invariant(left), .invariant(right)),
         let (.out(left), .out(right)),
         let (.in(left), .in(right)):
        return typeMatches(left, right)
    case (.star, .star):
        return true
    default:
        return false
    }
}

extension CallTypeChecker.MemberCallCollectionFlowContext {
    @discardableResult
    func bindBundledSequenceDestinationSourceFunction(
        typeArguments: [TypeID],
        parameterMapping: [Int: Int]? = nil,
        locals: inout LocalBindings
    ) -> Bool {
        let parameterMapping = parameterMapping
            ?? Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        guard isSequenceReceiver else {
            return false
        }
        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            calleeName,
        ]
        guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == args.count,
                  let signatureReceiver = signature.receiverType
            else {
                return false
            }
            return receiverClassifier.isSequenceLikeType(signatureReceiver)
        }) else {
            return false
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: typeArguments,
            parameterMapping: parameterMapping
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        for arg in args {
            if let expr = ast.arena.expr(arg.expr), expr.isLambdaOrCallableRef {
                sema.bindings.unmarkCollectionHOFLambdaExpr(arg.expr)
            }
        }
        return true
    }

    @discardableResult
    func bindBundledListSourceFunction(
        typeArguments: [TypeID],
        parameterMapping: [Int: Int]? = nil,
        matchingParameterType: TypeID? = nil,
        receiverElementType: TypeID? = nil,
        requireMutableListReceiver: Bool = false,
        locals: inout LocalBindings
    ) -> Bool {
        let parameterMapping = parameterMapping
            ?? Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        func typeMatches(_ lhs: TypeID, _ rhs: TypeID) -> Bool {
            let lk = sema.types.kind(of: lhs)
            let rk = sema.types.kind(of: rhs)
            switch (lk, rk) {
            case let (.classType(l), .classType(r)):
                return l.classSymbol == r.classSymbol
                    && l.nullability == r.nullability
                    && l.args.count == r.args.count
                    && zip(l.args, r.args).allSatisfy {
                        typeArgumentsMatch($0.0, $0.1, using: typeMatches)
                    }
            case let (.functionType(l), .functionType(r)):
                return l.nullability == r.nullability
                    && l.isSuspend == r.isSuspend
                    && l.params.count == r.params.count
                    && zip(l.params, r.params).allSatisfy(typeMatches)
                    && typeMatches(l.returnType, r.returnType)
                    && l.receiver == r.receiver
                    && l.throws == r.throws
            case let (.typeParam(l), .typeParam(r)):
                return l.symbol == r.symbol && l.nullability == r.nullability
            case let (.kClassType(l), .kClassType(r)):
                return l.nullability == r.nullability && typeMatches(l.argument, r.argument)
            case let (.primitive(l, lNull), .primitive(r, rNull)):
                return l == r && lNull == rNull
            case let (.nothing(lNull), .nothing(rNull)),
                 let (.any(lNull), .any(rNull)),
                 let (.stringStruct(lNull), .stringStruct(rNull)):
                return lNull == rNull
            case (.error, .error), (.unit, .unit), (.nullableUnit, .nullableUnit):
                return true
            default:
                return false
            }
        }
        guard (!isSequenceReceiver || isListFactoryReceiver),
              receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver
        else {
            return false
        }
        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            calleeName,
        ]
        guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == args.count,
                  let signatureReceiver = signature.receiverType
            else {
                return false
            }
            guard receiverClassifier.isConcreteListLikeType(signatureReceiver) else {
                return false
            }
            if requireMutableListReceiver,
               !receiverClassifier.isMutableListCollectionType(signatureReceiver)
            {
                return false
            }
            if let matchingParameterType,
               !signature.parameterTypes.isEmpty,
               !signature.typeParameterSymbols.isEmpty
            {
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                let substitution = Dictionary(uniqueKeysWithValues: typeArguments.enumerated().map {
                    (TypeVarID(rawValue: Int32($0.offset)), $0.element)
                })
                let substitutedParam = sema.types.substituteTypeParameters(
                    in: signature.parameterTypes[0],
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                guard typeMatches(substitutedParam, matchingParameterType) else {
                    return false
                }
            }
            if let receiverElementType {
                guard extractListElementType(
                    signatureReceiver,
                    sema: sema,
                    interner: interner
                ) == receiverElementType else {
                    return false
                }
            }
            return true
        }) else {
            return false
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: typeArguments,
            parameterMapping: parameterMapping
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        return true
    }

    /// Bind a source-backed `List.binarySearch` / `binarySearchBy` overload using
    /// the regular overload resolver so default arguments and named labels are
    /// handled correctly.
    @discardableResult
    func bindBundledListBinarySearchSource(elementType: TypeID, locals: inout LocalBindings) -> Bool {
        let calleeStr = interner.resolve(calleeName)
        guard calleeStr == "binarySearch" || calleeStr == "binarySearchBy" else { return false }
        guard (!isSequenceReceiver || isListFactoryReceiver),
              receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver
        else {
            return false
        }
        let sourceFQName = [interner.intern("kotlin"), interner.intern("collections"), calleeName]
        let candidates = sema.symbols.lookupAll(fqName: sourceFQName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let signatureReceiver = signature.receiverType
            else {
                return false
            }
            return receiverClassifier.isConcreteListLikeType(signatureReceiver)
        }
        guard !candidates.isEmpty else { return false }

        let callArgs: [CallArg] = args.map { arg in
            CallArg(label: arg.label, isSpread: arg.isSpread, type: sema.bindings.exprTypes[arg.expr] ?? sema.types.anyType)
        }
        let callExpr = CallExpr(range: range, calleeName: calleeName, args: callArgs)
        let resolved = OverloadResolver().resolveCall(
            candidates: candidates,
            call: callExpr,
            expectedType: sema.types.intType,
            implicitReceiverType: receiverType,
            ctx: sema
        )
        guard let chosenCallee = resolved.chosenCallee else { return false }
        _ = bindCallAndResolveReturnType(id, chosen: chosenCallee, resolved: resolved, sema: sema)
        return true
    }

    @discardableResult
    func bindBundledIterableSourceFunction(
        typeArguments: [TypeID],
        matchingParameterTypes: [TypeID]? = nil,
        enforceTypeParameterCount: Bool = false,
        matchingReceiverElementType: TypeID? = nil,
        allowNominalIterableReceiver: Bool = false,
        allowCollectionReceiver: Bool = false,
        allowConcreteForEachReceiver: Bool = false,
        receiverElementType: TypeID? = nil,
        locals: inout LocalBindings
    ) -> Bool {
        // KSP-978: Generic Iterable group-family calls use the bundled
        // source declarations. Concrete List receivers keep the List path
        // unless an exact specialized Iterable overload opts in below, and
        // the inline forEach family also routes concrete List/Set receivers.
        guard !isSequenceReceiver,
              ((allowCollectionReceiver && isCollectionReceiver)
                || (allowNominalIterableReceiver
                    ? (isIterableReceiver || !isCollectionReceiver)
                    : (isCollectionReceiver || (isIterableReceiver && (calleeStr == "none"
                    || calleeStr == "drop"
                    || calleeStr == "dropWhile"
                    || calleeStr == "runningReduce"
                    || calleeStr == "runningReduceIndexed"
                    || calleeStr == "groupBy"
                    || calleeStr == "groupByTo"
                    || calleeStr == "associate"
                    || calleeStr == "associateBy"
                    || calleeStr == "associateWith"
                    || calleeStr == "associateTo"
                    || calleeStr == "associateByTo"
                    || calleeStr == "associateWithTo"
                    || calleeStr == "find"
                    || isIterableFilterFamilyHOF))
                    || (isIterableIndexReceiver && isIterableIndexFamilyHOF)))
                || (allowConcreteForEachReceiver
                    && ((isListReceiver && !isEnumEntriesReceiver) || isSetReceiver)))
        else {
            return false
        }

        func typeMatches(_ lhs: TypeID, _ rhs: TypeID) -> Bool {
            let lhsKind = sema.types.kind(of: lhs)
            let rhsKind = sema.types.kind(of: rhs)
            switch (lhsKind, rhsKind) {
            case let (.classType(l), .classType(r)):
                return l.classSymbol == r.classSymbol
                    && l.nullability == r.nullability
                    && l.args.count == r.args.count
                    && zip(l.args, r.args).allSatisfy {
                        typeArgumentsMatch($0.0, $0.1, using: typeMatches)
                    }
            case let (.functionType(l), .functionType(r)):
                return l.nullability == r.nullability
                    && l.isSuspend == r.isSuspend
                    && l.params.count == r.params.count
                    && zip(l.params, r.params).allSatisfy(typeMatches)
                    && typeMatches(l.returnType, r.returnType)
                    && l.receiver == r.receiver
                    && l.throws == r.throws
            case let (.typeParam(l), .typeParam(r)):
                return l.symbol == r.symbol && l.nullability == r.nullability
            case let (.kClassType(l), .kClassType(r)):
                return l.nullability == r.nullability && typeMatches(l.argument, r.argument)
            case let (.primitive(l, lNullability), .primitive(r, rNullability)):
                return l == r && lNullability == rNullability
            case let (.nothing(lNullability), .nothing(rNullability)),
                 let (.any(lNullability), .any(rNullability)),
                 let (.stringStruct(lNullability), .stringStruct(rNullability)):
                return lNullability == rNullability
            case (.error, .error), (.unit, .unit), (.nullableUnit, .nullableUnit):
                return true
            default:
                return false
            }
        }
        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            calleeName,
        ]
        let receiverForLookup = sema.types.makeNonNullable(receiverType)
        guard let (actualReceiverClassType, _) = resolveClassTypeSymbol(receiverForLookup, sema: sema) else {
            return false
        }
        let actualClassSymbol = actualReceiverClassType.classSymbol
        guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == args.count,
                  let signatureReceiver = signature.receiverType
            else {
                return false
            }
            if enforceTypeParameterCount,
               signature.typeParameterSymbols.count != typeArguments.count
            {
                return false
            }
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let substitution = Dictionary(uniqueKeysWithValues: typeArguments.enumerated().map {
                (TypeVarID(rawValue: Int32($0.offset)), $0.element)
            })
            if let matchingParameterTypes,
               matchingParameterTypes.count == signature.parameterTypes.count,
               !signature.typeParameterSymbols.isEmpty
            {
                for (parameterType, matchingType) in zip(signature.parameterTypes, matchingParameterTypes) {
                    let substitutedParameterType = sema.types.substituteTypeParameters(
                        in: parameterType,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    )
                    guard typeMatches(substitutedParameterType, matchingType) else {
                        return false
                    }
                }
            }
            if let matchingReceiverElementType,
               let (receiverClassType, _) = resolveClassTypeSymbol(
                   sema.types.substituteTypeParameters(
                       in: signatureReceiver,
                       substitution: substitution,
                       typeVarBySymbol: typeVarBySymbol
                   ),
                   sema: sema
               ),
               let receiverArgument = receiverClassType.args.first
            {
                let receiverElementType: TypeID = switch receiverArgument {
                case let .invariant(type), let .out(type), let .in(type): type
                case .star: sema.types.anyType
                }
                if !typeMatches(receiverElementType, matchingReceiverElementType) {
                    // Source signatures retain their receiver type parameter
                    // in this fast path. The call-site type argument is the
                    // authoritative substitution for the exact Iterable
                    // owner when the structural TypeID substitution above
                    // cannot rewrite that receiver slot.
                    guard typeArguments.first == matchingReceiverElementType,
                          case .typeParam = sema.types.kind(of: receiverElementType)
                    else {
                        return false
                    }
                }
            }
            if let receiverElementType,
               getCollectionElementType(signatureReceiver, sema: sema, interner: interner) != receiverElementType {
                return false
            }
            if isCollectionLikeType(signatureReceiver, sema: sema, interner: interner),
               let (sigClassType, _) = resolveClassTypeSymbol(signatureReceiver, sema: sema),
               sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol) {
                return true
            }
            guard let (sigClassType, receiverSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema) else {
                return false
            }
            if receiverSymbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ], sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol) {
                return true
            }
            return false
        }) else {
            return false
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: typeArguments,
            parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        return true
    }

    /// KUU-542: true when the argument is typed as `kotlin.Comparator` (or a
    /// nominal subtype). The bundled `Iterable` `*With`/`sortedWith`
    /// overloads only take Comparator parameters, so a function-typed
    /// argument must not bind to them.
    func isComparatorTypedArgument(_ argExprID: ExprID, locals: inout LocalBindings) -> Bool {
        let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
        guard let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName),
              let argType = sema.bindings.exprType(for: argExprID),
              case let .classType(argClassType) = sema.types.kind(of: sema.types.makeNonNullable(argType))
        else {
            return false
        }
        return sema.types.isNominalSubtypeSymbol(argClassType.classSymbol, of: comparatorSymbol)
    }

    /// Bind the source-backed `Iterable<T>.sum()` overload. The caller
    /// tries the concrete `List<Int>.sum()` fast path first for List-like
    /// receivers (BUG-256: that path only has an `Int` overload in
    /// ListCollectionOps.kt, so every other element type falls through to
    /// this function); call order, not a guard here, keeps the List fast
    /// path from being overridden when it already bound.
    func bindBundledIterableSumSource(locals: inout LocalBindings) -> TypeID? {
        guard !isSequenceReceiver,
              !isRangeReceiver,
              isCollectionReceiver,
              args.isEmpty
        else {
            return nil
        }
        let collectionElementType = getCollectionElementType(
            receiverType,
            sema: sema,
            interner: interner
        )
        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            calleeName,
        ]
        let chosen = sema.symbols.lookupAll(fqName: sourceFQName).first { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty,
                  let signatureReceiver = signature.receiverType,
                  receiverClassifier.isIterableLikeType(signatureReceiver)
            else {
                return false
            }
            return extractIterableOrSequenceElementType(
                signatureReceiver,
                sema: sema,
                interner: interner
            ) == collectionElementType
        }
        guard let chosen,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: [],
            parameterMapping: [:]
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        return signature.returnType
    }

    /// Select and bind one of the source-backed generic `<T> Iterable<T>.sumOf`
    /// overloads by the already-known selector return type, substituting
    /// each candidate's own `T` for `collectionElementType` first --
    /// `signature.receiverType`/`parameterTypes` carry the *unsubstituted*
    /// type parameter, so comparing them against a concrete element type
    /// directly (as this used to do) always fails. Shared by
    /// `bindBundledIterableSumOfSource` (first attempt, before the lambda
    /// has been inferred) and the `List<T>.sumOf` fallback (BUG-256
    /// sibling: `ListAggregateHOF.kt` only has Int/Long/Double concrete
    /// overloads; the caller already inferred the lambda once against
    /// that set, so inferring it again here would double-register the
    /// same HOF lambda expr).
    func bindIterableSumOfSourceForSelectorType(
        collectionElementType: TypeID,
        selectorReturnType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            calleeName,
        ]
        let iterableFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        let chosen = sema.symbols.lookupAll(fqName: sourceFQName).first { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let signatureReceiver = signature.receiverType,
                  // This helper is specifically for the generic
                  // Iterable<T>.sumOf overloads. A List<T> receiver is
                  // Iterable-like too, but its indexed List.sumOf body
                  // is not valid for Set/Collection receivers.
                  let (_, receiverSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema),
                  receiverSymbol.fqName == iterableFQName,
                  !signature.typeParameterSymbols.isEmpty
            else {
                return false
            }
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let substitution: [TypeVarID: TypeID] = [TypeVarID(rawValue: 0): collectionElementType]
            let substitutedReceiver = sema.types.substituteTypeParameters(
                in: signatureReceiver,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            guard extractIterableOrSequenceElementType(
                substitutedReceiver,
                sema: sema,
                interner: interner
            ) == collectionElementType else {
                return false
            }
            let substitutedParam = sema.types.substituteTypeParameters(
                in: signature.parameterTypes[0],
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            guard case let .functionType(selectorType) = sema.types.kind(of: substitutedParam),
                  selectorType.params.count == 1,
                  selectorType.params[0] == collectionElementType
            else {
                return false
            }
            return selectorType.returnType == selectorReturnType
        }
        guard let chosen,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: [collectionElementType],
            parameterMapping: [0: 0]
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        return signature.returnType
    }

    /// Bind one of the five source-backed `Iterable<T>.sumOf` overloads by
    /// the selector body's actual return type. This is the target-specific
    /// counterpart of the general collection HOF path; List and Sequence
    /// overload resolution remains on their existing paths.
    func bindBundledIterableSumOfSource(locals: inout LocalBindings) -> TypeID? {
        guard !isSequenceReceiver,
              !isRangeReceiver,
              isCollectionReceiver,
              args.count == 1,
              !receiverClassifier.isConcreteListLikeType(receiverType)
        else {
            return nil
        }
        let collectionElementType = getCollectionElementType(
            receiverType,
            sema: sema,
            interner: interner
        )
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: [collectionElementType],
            returnType: sema.types.anyType
        )))
        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        }
        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
        let selectorReturnType = inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
        guard let returnType = bindIterableSumOfSourceForSelectorType(
            collectionElementType: collectionElementType,
            selectorReturnType: selectorReturnType
        , locals: &locals) else {
            return nil
        }
        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
        }
        return returnType
    }

    @discardableResult
    func bindBundledIterableFlatMapSourceFunction(
        collectionElementType: TypeID,
        resultElementType: TypeID,
        returnsSequence: Bool,
        destinationType: TypeID? = nil,
        locals: inout LocalBindings
    ) -> Bool {
        // KSP-974: select the Iterable receiver's overload by the lambda
        // return type before lowering, including indexed and destination transforms.
        guard !isSequenceReceiver,
              isIterableReceiver,
              !receiverClassification.isListReceiver,
              !receiverClassification.isSetReceiver,
              !receiverClassification.isMapReceiver
        else {
            return false
        }
        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            calleeName,
        ]
        let iterableFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        let sequenceFQName = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]
        guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == args.count,
                  let signatureReceiver = signature.receiverType,
                  let receiverSymbol = resolveClassTypeSymbol(signatureReceiver, sema: sema)?.1,
                  receiverSymbol.fqName == iterableFQName,
                  let transformTypeIndex = signature.parameterTypes.indices.last,
                  case let .functionType(transformType) = sema.types.kind(of: signature.parameterTypes[transformTypeIndex]),
                  let returnSymbol = resolveClassTypeSymbol(transformType.returnType, sema: sema)?.1
            else {
                return false
            }
            let returnFQName = returnSymbol.fqName
            if returnsSequence {
                return returnFQName == sequenceFQName
            }
            return returnFQName == iterableFQName
        }) else {
            return false
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: destinationType.map {
                [collectionElementType, resultElementType, $0]
            } ?? [collectionElementType, resultElementType],
            parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        for argument in args {
            if let lambdaExpr = ast.arena.expr(argument.expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
            }
        }
        return true
    }

    @discardableResult
    func bindBundledAsSequenceSourceIfAvailable(typeArguments: [TypeID], locals: inout LocalBindings) -> Bool {
        // Sequence.asSequence() is an identity conversion. The bundled
        // Iterable.asSequence() implementation is only valid for an
        // Iterable receiver; binding it to Sequence produces an empty
        // result because Sequence is not an Iterable in Kotlin.
        guard !isSequenceReceiver,
              (isCollectionReceiver || isIterableReceiver),
              !isArrayReceiver,
              args.isEmpty else {
            return false
        }
        guard interner.resolve(calleeName) == "asSequence" else {
            return false
        }
        // KSP-1003: Map.asSequence() has its own source-backed overload.
        // Do not let the generic Iterable fallback treat Map as a
        // collection expression; Map is not an Iterable in Kotlin.
        if isMapReceiver, bindBundledMapSourceFunction(locals: &locals) {
            return true
        }
        let sourcePackages: [[InternedString]] = [
            [interner.intern("kotlin"), interner.intern("sequences")],
            [interner.intern("kotlin"), interner.intern("collections")],
        ]
        for packageFQName in sourcePackages {
            if let chosenCallee = sema.symbols.lookupAll(fqName: packageFQName + [calleeName]).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                let signatureIsSequence = receiverClassifier.isSequenceLikeType(signatureReceiver)
                // Sequence<T> is marked as a collection expression while
                // its static type is being inferred. Do not let that
                // heuristic select Iterable<T>.asSequence(): Kotlin's
                // Sequence<T>.asSequence() overload is the identity
                // conversion and must win for a Sequence receiver.
                if isSequenceReceiver {
                    return signatureIsSequence
                }
                if signatureIsSequence {
                    return false
                }
                return receiverClassifier.isIterableLikeType(signatureReceiver)
                    || receiverClassifier.isCollectionLikeType(signatureReceiver)
            }) {
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: typeArguments,
                    parameterMapping: [:]
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                return true
            }
        }
        return false
    }

    func typeIDFromTypeArg(_ typeArg: TypeArg) -> TypeID {
        switch typeArg {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            sema.types.anyType
        }
    }

    func containsTypeParameter(_ typeID: TypeID, symbols: Set<SymbolID>, locals: inout LocalBindings) -> Bool {
        switch sema.types.kind(of: typeID) {
        case let .typeParam(typeParam):
            symbols.contains(typeParam.symbol)
        case let .classType(classType):
            classType.args.contains { arg in
                containsTypeParameter(arg, symbols: symbols, locals: &locals)
            }
        case let .functionType(functionType):
            (functionType.receiver.map { containsTypeParameter($0, symbols: symbols, locals: &locals) } ?? false)
                || functionType.params.contains { containsTypeParameter($0, symbols: symbols, locals: &locals) }
                || containsTypeParameter(functionType.returnType, symbols: symbols, locals: &locals)
                || functionType.contextReceivers.contains { containsTypeParameter($0, symbols: symbols, locals: &locals) }
        case let .kClassType(kClassType):
            containsTypeParameter(kClassType.argument, symbols: symbols, locals: &locals)
        case let .intersection(parts):
            parts.contains { containsTypeParameter($0, symbols: symbols, locals: &locals) }
        default:
            false
        }
    }

    func containsTypeParameter(_ typeArg: TypeArg, symbols: Set<SymbolID>, locals: inout LocalBindings) -> Bool {
        switch typeArg {
        case let .invariant(type), let .out(type), let .in(type):
            containsTypeParameter(type, symbols: symbols, locals: &locals)
        case .star:
            false
        }
    }

    func mapExtraTypeArgument(
        signatureReturnType: TypeID,
        actualLambdaReturnType: TypeID,
        extraSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner,
        locals: inout LocalBindings
    ) -> TypeID? {
        let extraSymbols: Set<SymbolID> = [extraSymbol]
        guard containsTypeParameter(signatureReturnType, symbols: extraSymbols, locals: &locals) else {
            return nil
        }
        switch sema.types.kind(of: signatureReturnType) {
        case let .typeParam(typeParam) where typeParam.symbol == extraSymbol:
            if typeParam.nullability == .nullable {
                return sema.types.makeNonNullable(actualLambdaReturnType)
            }
            return actualLambdaReturnType
        case let .classType(classType):
            if classType.args.count == 1,
               containsTypeParameter(typeIDFromTypeArg(classType.args[0]), symbols: extraSymbols, locals: &locals) {
                return extractIterableOrSequenceElementType(actualLambdaReturnType, sema: sema, interner: interner)
            }
        default:
            break
        }
        return nil
    }

    /// Bind a member call to a bundled Kotlin-source extension declared on a
    /// collection owner interface (`Map`, `Set`, …), inferring the owner's type
    /// arguments from the receiver and any remaining ones from lambda returns.
    @discardableResult
    func bindBundledCollectionOwnerSourceFunction(
        receiverTypeArgumentCount: Int,
        matchingLambdaReturnType: TypeID? = nil,
        locals: inout LocalBindings,
        isOwnerSymbol: (SemanticSymbol) -> Bool
    ) -> Bool {
        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            calleeName,
        ]
        let receiverForLookup = sema.types.makeNonNullable(receiverType)
        guard let (actualReceiverClassType, _) = resolveClassTypeSymbol(receiverForLookup, sema: sema),
              actualReceiverClassType.args.count >= receiverTypeArgumentCount
        else {
            return false
        }
        let actualClassSymbol = actualReceiverClassType.classSymbol
        let sourceCandidates = sema.symbols.lookupAll(fqName: sourceFQName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == args.count,
                  let signatureReceiver = signature.receiverType
            else {
                return false
            }
            guard let (sigClassType, sigSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema),
                  isOwnerSymbol(sigSymbol)
            else {
                return false
            }
            return sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol)
        }
        let chosenCallee: SymbolID?
        if let matchingLambdaReturnType {
            let exactCandidate = sourceCandidates.first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.parameterTypes.contains { parameterType in
                    guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                        return false
                    }
                    return functionType.returnType == matchingLambdaReturnType
                        || (sema.types.isSubtype(functionType.returnType, matchingLambdaReturnType)
                            && sema.types.isSubtype(matchingLambdaReturnType, functionType.returnType))
                }
            })
            chosenCallee = exactCandidate ?? sourceCandidates.first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.parameterTypes.contains { parameterType in
                    guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                        return false
                    }
                    if case .typeParam = sema.types.kind(of: functionType.returnType) {
                        return true
                    }
                    return false
                }
            }) ?? sourceCandidates.first
        } else {
            chosenCallee = sourceCandidates.first
        }
        guard let chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosenCallee)
        else {
            return false
        }
        let baseCount = min(
            max(signature.classTypeParameterCount, actualReceiverClassType.args.count),
            signature.typeParameterSymbols.count
        )
        var typeArguments: [TypeID] = []
        for index in 0..<baseCount {
            if index < actualReceiverClassType.args.count {
                typeArguments.append(typeIDFromTypeArg(actualReceiverClassType.args[index]))
            } else {
                typeArguments.append(sema.types.anyType)
            }
        }
        let extraParamSymbols = Array(signature.typeParameterSymbols.dropFirst(typeArguments.count))
        if !extraParamSymbols.isEmpty {
            var inferredExtras: [TypeID?] = Array(repeating: nil, count: extraParamSymbols.count)
            // Destination-type parameters such as `C`/`M` appear directly in
            // the first value parameter, so infer them from the actual
            // destination before inferring transform-result parameters.
            if isMapReceiver {
                for (argIndex, parameterType) in signature.parameterTypes.enumerated() {
                    guard argIndex < args.count,
                          case let .typeParam(parameterTypeParam) = sema.types.kind(of: parameterType),
                          let extraIndex = extraParamSymbols.firstIndex(of: parameterTypeParam.symbol)
                    else {
                        continue
                    }
                    let actualArgumentType = sema.bindings.exprTypes[args[argIndex].expr] ?? sema.types.anyType
                    inferredExtras[extraIndex] = sema.types.makeNonNullable(actualArgumentType)
                }
            }
            var inferredLambdaArgExpr: ExprID?
            for (argIndex, paramType) in signature.parameterTypes.enumerated() {
                guard case let .functionType(fn) = sema.types.kind(of: paramType) else {
                    continue
                }
                let paramReturnType = fn.returnType
                guard containsTypeParameter(paramReturnType, symbols: Set(extraParamSymbols), locals: &locals) else {
                    continue
                }
                let actualArgExpr = args[argIndex].expr
                let actualLambdaReturnType = inferredLambdaReturnType(argExpr: actualArgExpr, ast: ast, sema: sema)
                var extrasForParam: [TypeID] = []
                for (extraIndex, extraSymbol) in extraParamSymbols.enumerated() {
                    if let inferred = inferredExtras[extraIndex] {
                        extrasForParam.append(inferred)
                        continue
                    }
                    if let inferred = mapExtraTypeArgument(
                        signatureReturnType: paramReturnType,
                        actualLambdaReturnType: actualLambdaReturnType,
                        extraSymbol: extraSymbol,
                        sema: sema,
                        interner: interner
                    , locals: &locals) {
                        extrasForParam.append(inferred)
                    } else {
                        extrasForParam.append(sema.types.anyType)
                    }
                }
                if extrasForParam.count == extraParamSymbols.count {
                    inferredExtras = extrasForParam.map(Optional.some)
                    inferredLambdaArgExpr = actualArgExpr
                    break
                }
            }
            if let inferredLambdaArgExpr {
                sema.bindings.unmarkCollectionHOFLambdaExpr(inferredLambdaArgExpr)
            }
            typeArguments.append(contentsOf: inferredExtras.map { $0 ?? sema.types.anyType })
            if typeArguments.count < signature.typeParameterSymbols.count {
                typeArguments.append(contentsOf: Array(repeating: sema.types.anyType, count: signature.typeParameterSymbols.count - typeArguments.count))
            }
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: typeArguments,
            parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        return true
    }

    @discardableResult
    func bindBundledMapSourceFunction(matchingLambdaReturnType: TypeID? = nil, locals: inout LocalBindings) -> Bool {
        guard isMapReceiver, !isSequenceReceiver else {
            return false
        }
        return bindBundledCollectionOwnerSourceFunction(
            receiverTypeArgumentCount: 2,
            matchingLambdaReturnType: matchingLambdaReturnType
        , locals: &locals) {
            knownNames.isMapLikeSymbol($0)
        }
    }

    // KSP-957: onEach/onEachIndexed use the Kotlin self-type form
    // `<T, C : Iterable<T>> C` and `<K, V, M : Map<out K, V>> M`.
    // The generic receiver type parameter is not handled by the regular
    // collection-owner resolver, so bind the source declaration after the
    // lambda has been contextualized.
    @discardableResult
    func bindBundledGenericOnEachSourceFunction(typeArguments: [TypeID], locals: inout LocalBindings) -> Bool {
        guard !isSequenceReceiver,
              !isArrayReceiver,
              args.count == 1,
              typeArguments.count == (isMapReceiver ? 3 : 2)
        else {
            return false
        }
        let ownerName = isMapReceiver ? "Map" : "Iterable"
        let ownerFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern(ownerName),
        ]
        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            calleeName,
        ]
        let sourceCandidates = sema.symbols.lookupAll(fqName: sourceFQName)
        guard let chosenCallee = sourceCandidates.first(where: { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == args.count,
                  signature.typeParameterSymbols.count == typeArguments.count,
                  let signatureReceiver = signature.receiverType,
                  case let .typeParam(receiverParameter) = sema.types.kind(of: sema.types.makeNonNullable(signatureReceiver)),
                  signature.typeParameterSymbols.last == receiverParameter.symbol,
                  case let .typeParam(returnParameter) = sema.types.kind(of: sema.types.makeNonNullable(signature.returnType)),
                  returnParameter.symbol == receiverParameter.symbol
            else {
                return false
            }
            let receiverParameterIndex = signature.typeParameterSymbols.firstIndex(of: receiverParameter.symbol)
            let signatureUpperBounds = receiverParameterIndex
                .flatMap { index in
                    index < signature.typeParameterUpperBoundsList.count
                        ? signature.typeParameterUpperBoundsList[index]
                        : nil
                }
                ?? []
            let upperBounds = signatureUpperBounds
                + sema.symbols.typeParameterUpperBounds(for: receiverParameter.symbol)
                    .filter { !signatureUpperBounds.contains($0) }
            return upperBounds.contains { bound in
                guard let (_, boundSymbol) = resolveClassTypeSymbol(bound, sema: sema) else {
                    return false
                }
                return boundSymbol.fqName == ownerFQName
            }
        }) else {
            return false
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: typeArguments,
            parameterMapping: [0: 0]
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        return true
    }

    /// KSP-1011: Bind `map.iterator()` straight to the bundled
    /// `Map<out K, V>.__kspMapIterator()` source declaration. That
    /// declaration is deliberately *not* named `iterator`: a second
    /// source-backed function named `iterator` in `kotlin.collections`
    /// widens the by-simple-name candidate pool that the generic
    /// `Iterable<T>.iterator()` call inside bundled HOFs (`reduce`,
    /// `reduceIndexed`, ...) resolves against, and that lookup does not
    /// filter candidates by nominal receiver compatibility — it matched
    /// this Map-only function for every Iterable receiver, including
    /// ranges, and crashed at runtime. Keeping the call-site name
    /// (`iterator`) but the target name mangled avoids widening that
    /// pool while still binding the correct implementation here.
    func bindBundledMapIteratorSourceFunction(locals: inout LocalBindings) -> TypeID? {
        // MutableMap.iterator() has a more specific source-backed overload
        // whose mutable entry type and runtime bridge must win. Let the
        // regular member resolver select that overload instead of binding
        // the read-only Map iterator first.
        guard isMapReceiver,
              !isSequenceReceiver,
              !receiverClassifier.isMutableMapType(receiverType),
              calleeStr == "iterator",
              args.isEmpty
        else {
            return nil
        }
        let sourceFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("__kspMapIterator"),
        ]
        let receiverForLookup = sema.types.makeNonNullable(receiverType)
        guard let (actualReceiverClassType, _) = resolveClassTypeSymbol(receiverForLookup, sema: sema),
              actualReceiverClassType.args.count >= 2
        else {
            return nil
        }
        let actualClassSymbol = actualReceiverClassType.classSymbol
        guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty,
                  let signatureReceiver = signature.receiverType,
                  let (sigClassType, sigSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema)
            else {
                return false
            }
            return knownNames.isMapLikeSymbol(sigSymbol)
                && sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol)
        }),
              let signature = sema.symbols.functionSignature(for: chosenCallee)
        else {
            return nil
        }

        let typeArguments = actualReceiverClassType.args.prefix(2).map(typeIDFromTypeArg)
        guard typeArguments.count == signature.typeParameterSymbols.count else {
            return nil
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: typeArguments,
            parameterMapping: [:]
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (symbol, type) in zip(signature.typeParameterSymbols, typeArguments) {
            if let typeVar = typeVarBySymbol[symbol] {
                substitution[typeVar] = type
            }
        }
        return sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    // KSP-432/KSP-704: Set members are source-backed in
    // Stdlib/kotlin/collections/Set.kt and SetHOF.kt.
    @discardableResult
    func bindBundledSetSourceFunction(locals: inout LocalBindings) -> Bool {
        guard isSetReceiver, !isSequenceReceiver, !isMapReceiver else {
            return false
        }
        return bindBundledCollectionOwnerSourceFunction(receiverTypeArgumentCount: 1, locals: &locals) {
            knownNames.isSetLikeSymbol($0)
        }
    }

    func sequenceSourceReceiverElementMatches(
        _ signature: FunctionSignature,
        actualElementType: TypeID,
        locals: inout LocalBindings
    ) -> Bool {
        // Generic Sequence<T> extensions accept every element type. A
        // monomorphic extension, however, must only be selected when
        // its concrete receiver element matches the actual receiver.
        guard signature.typeParameterSymbols.isEmpty,
              let signatureReceiver = signature.receiverType
        else {
            return true
        }
        return extractIterableOrSequenceElementType(
            signatureReceiver,
            sema: sema,
            interner: interner
        ) == actualElementType
    }


    func bindBundledSequenceAggregateSource(typeArguments: [TypeID], locals: inout LocalBindings) {
        guard isSequenceReceiver else {
            return
        }
        let sourcePackages: [[InternedString]] = [
            [interner.intern("kotlin"), interner.intern("sequences")],
            [interner.intern("kotlin"), interner.intern("collections")],
        ]
        var chosenCallee: SymbolID?
        for packageFQName in sourcePackages {
            if let candidate = sema.symbols.lookupAll(fqName: packageFQName + [calleeName]).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                return receiverClassifier.isSequenceLikeType(signatureReceiver)
                    && sequenceSourceReceiverElementMatches(
                        signature,
                        actualElementType: collectionElementType
                    , locals: &locals)
            }) {
                chosenCallee = candidate
                break
            }
        }
        guard let chosenCallee else {
            return
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: typeArguments,
            parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        for arg in args {
            if let expr = ast.arena.expr(arg.expr), expr.isLambdaOrCallableRef {
                sema.bindings.unmarkCollectionHOFLambdaExpr(arg.expr)
            }
        }
    }


    /// KSP-1359: bind the bundled monomorphic `Sequence<E>.sum()`
    /// overload whose receiver element type matches the actual
    /// receiver's element type, and return its declared return type
    /// (Double/Float/Long/UInt/ULong sibling of `Sequence<Int>.sum()`).
    /// The Sequence counterpart of `bindBundledIterableSumSource`,
    /// which cannot be reused here because it only scans the
    /// kotlin.collections Iterable-family declarations.
    func bindBundledSequenceSumSource(locals: inout LocalBindings) -> TypeID? {
        guard isSequenceReceiver, args.isEmpty else {
            return nil
        }
        let sourcePackages: [[InternedString]] = [
            [interner.intern("kotlin"), interner.intern("sequences")],
            [interner.intern("kotlin"), interner.intern("collections")],
        ]
        for packageFQName in sourcePackages {
            if let chosen = sema.symbols.lookupAll(fqName: packageFQName + [calleeName]).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.isEmpty,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                return receiverClassifier.isSequenceLikeType(signatureReceiver)
                    && sequenceSourceReceiverElementMatches(
                        signature,
                        actualElementType: collectionElementType
                    , locals: &locals)
            }) {
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                return sema.symbols.functionSignature(for: chosen)?.returnType
            }
        }
        return nil
    }


    /// KSP-1359: select and bind the bundled generic
    /// `<T> Sequence<T>.sumOf(selector)` overload whose selector return
    /// type equals `selectorReturnType`, substituting each candidate's
    /// `T` for the concrete element type first (its signature stores
    /// the unsubstituted type parameter). The Sequence counterpart of
    /// `bindIterableSumOfSourceForSelectorType`: without a
    /// selector-type-aware match, the first arity-compatible overload
    /// would capture every selector type (upstream exposes exactly the
    /// Int/Long/Double/UInt/ULong family).
    func bindSequenceSumOfSourceForSelectorType(
        selectorReturnType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sourcePackages: [[InternedString]] = [
            [interner.intern("kotlin"), interner.intern("sequences")],
            [interner.intern("kotlin"), interner.intern("collections")],
        ]
        for packageFQName in sourcePackages {
            if let chosen = sema.symbols.lookupAll(fqName: packageFQName + [calleeName]).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let signatureReceiver = signature.receiverType,
                      receiverClassifier.isSequenceLikeType(signatureReceiver),
                      !signature.typeParameterSymbols.isEmpty
                else {
                    return false
                }
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                let substitution: [TypeVarID: TypeID] = [TypeVarID(rawValue: 0): collectionElementType]
                let substitutedReceiver = sema.types.substituteTypeParameters(
                    in: signatureReceiver,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                guard extractIterableOrSequenceElementType(
                    substitutedReceiver,
                    sema: sema,
                    interner: interner
                ) == collectionElementType else {
                    return false
                }
                let substitutedParam = sema.types.substituteTypeParameters(
                    in: signature.parameterTypes[0],
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                guard case let .functionType(selectorType) = sema.types.kind(of: substitutedParam),
                      selectorType.params.count == 1,
                      selectorType.params[0] == collectionElementType
                else {
                    return false
                }
                return selectorType.returnType == selectorReturnType
            }) {
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [collectionElementType],
                    parameterMapping: [0: 0]
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                return sema.symbols.functionSignature(for: chosen)?.returnType
            }
        }
        return nil
    }


    // KSP-441: Source-backed Sequence transforms (map/filter/etc.) live in
    // kotlin.sequences as top-level extensions. Prefer them over the synthetic
    // runtime stubs so the object-expression pipeline runs.
    // `allowIterableReceiver` lets a plain `Iterable<T>`-typed receiver
    // (e.g. `val x: Iterable<Int> = setOf(...)`) fall back to the
    // bundled `Sequence<T>` source implementation for aggregate HOFs
    // that have no direct Iterable source declaration. The Sequence
    // source bodies are plain `for (element in this)` iteration, so
    // they are valid for a Set/other Iterable receiver as for a real
    // Sequence.
    func bindBundledSequenceSourceIfAvailable(
        resultType: TypeID,
        otherElementType: TypeID? = nil,
        overrideTypeArguments: [TypeID]? = nil,
        allowIterableReceiver: Bool = false,
        locals: inout LocalBindings
    ) -> Bool {
        guard isSequenceReceiver || (allowIterableReceiver && isCollectionReceiver) else {
            return false
        }
        let knownNames = KnownCompilerNames(interner: interner)
        let resultElementType: TypeID = if let classType = resolveClassType(resultType, sema: sema),
                                              classType.args.count >= 1,
                                              let classSymbolInfo = sema.symbols.symbol(classType.classSymbol),
                                              knownNames.isSequenceSymbol(classSymbolInfo) {
            switch classType.args[0] {
            case let .invariant(id), let .out(id), let .in(id):
                id
            case .star:
                collectionElementType
            }
        } else {
            collectionElementType
        }
        let sourcePackages: [[InternedString]] = [
            [interner.intern("kotlin"), interner.intern("sequences")],
            [interner.intern("kotlin"), interner.intern("collections")],
        ]
        var chosenCallee: SymbolID?
        for packageFQName in sourcePackages {
            let candidates = sema.symbols.lookupAll(fqName: packageFQName + [calleeName]).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                return receiverClassifier.isSequenceLikeType(signatureReceiver)
                    && sequenceSourceReceiverElementMatches(
                        signature,
                        actualElementType: collectionElementType
                    , locals: &locals)
            }

            // `Sequence<Sequence<T>>.flatten()` and
            // `Sequence<Iterable<T>>.flatten()` are both generic
            // source declarations. Prefer the candidate whose inner
            // receiver owner matches the actual element type. Calls
            // whose element type satisfies neither (or both)
            // constraints were already rejected in `case "flatten"`
            // (KUU-461), so the first-candidate fallback is only a
            // safety net here.
            var bestCandidate: SymbolID?
            var bestScore = Int.min
            for candidate in candidates {
                var score = 0
                if calleeName == interner.intern("flatten"),
                   let actualElementClassType = resolveClassTypeSymbol(
                       collectionElementType,
                       sema: sema
                   )?.0,
                   let signatureReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                   let candidateElementClassType = resolveClassTypeSymbol(
                       getCollectionElementType(signatureReceiver, sema: sema, interner: interner),
                       sema: sema
                   )?.0
                {
                    let actualElementSymbol = actualElementClassType.classSymbol
                    let candidateElementSymbol = candidateElementClassType.classSymbol
                    if candidateElementSymbol == actualElementSymbol {
                        score = 2
                    } else if sema.types.isNominalSubtypeSymbol(
                        actualElementSymbol,
                        of: candidateElementSymbol
                    ) {
                        score = 1
                    }
                }
                if score > bestScore {
                    bestCandidate = candidate
                    bestScore = score
                }
            }
            if let bestCandidate {
                chosenCallee = bestCandidate
                break
            }
        }
        guard let chosenCallee else {
            return false
        }
        let typeParamCount = sema.symbols.functionSignature(for: chosenCallee)?.typeParameterSymbols.count ?? 0
        let typeArguments: [TypeID] = if let overrideTypeArguments {
            overrideTypeArguments
        } else if typeParamCount == 1 {
            [resultElementType]
        } else if typeParamCount == 2 {
            if let otherElementType {
                [collectionElementType, otherElementType]
            } else {
                [collectionElementType, resultElementType]
            }
        } else if typeParamCount == 3, let otherElementType {
            [collectionElementType, otherElementType, resultElementType]
        } else {
            []
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: typeArguments,
            parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        for arg in args {
            if let expr = ast.arena.expr(arg.expr), expr.isLambdaOrCallableRef {
                sema.bindings.unmarkCollectionHOFLambdaExpr(arg.expr)
            }
        }
        return true
    }

}

// swiftlint:enable cyclomatic_complexity file_length function_body_length
