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

private func collectionFlowTypeMatches(
    _ lhs: TypeID,
    _ rhs: TypeID,
    types: TypeSystem
) -> Bool {
    let lhsKind = types.kind(of: lhs)
    let rhsKind = types.kind(of: rhs)
    switch (lhsKind, rhsKind) {
    case let (.classType(l), .classType(r)):
        return l.classSymbol == r.classSymbol
            && l.nullability == r.nullability
            && l.args.count == r.args.count
            && zip(l.args, r.args).allSatisfy {
                typeArgumentsMatch($0.0, $0.1, using: { collectionFlowTypeMatches($0, $1, types: types) })
            }
    case let (.functionType(l), .functionType(r)):
        return l.nullability == r.nullability
            && l.isSuspend == r.isSuspend
            && l.params.count == r.params.count
            && zip(l.params, r.params).allSatisfy { collectionFlowTypeMatches($0, $1, types: types) }
            && collectionFlowTypeMatches(l.returnType, r.returnType, types: types)
            && l.receiver == r.receiver
            && l.throws == r.throws
    case let (.typeParam(l), .typeParam(r)):
        return l.symbol == r.symbol && l.nullability == r.nullability
    case let (.kClassType(l), .kClassType(r)):
        return l.nullability == r.nullability
            && collectionFlowTypeMatches(l.argument, r.argument, types: types)
    case let (.primitive(l, lNullability), .primitive(r, rNullability)):
        return l == r && lNullability == rNullability
    case let (.nothing(lNullability), .nothing(rNullability)),
         let (.any(lNullability), .any(rNullability)),
         let (.stringStruct(lNullability), .stringStruct(rNullability)):
        return lNullability == rNullability
    case (.error, .error), (.unit, .unit), (.nullableUnit, .nullableUnit), (.platformUnit, .platformUnit):
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
        returnsSequence: Bool? = nil) -> Bool {
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
                  let signatureReceiver = signature.receiverType,
                  receiverClassifier.isSequenceLikeType(signatureReceiver)
            else {
                return false
            }
            guard let returnsSequence else {
                return true
            }
            guard let transformParameterIndex = signature.parameterTypes.indices.last,
                  case let .functionType(transformType) = sema.types.kind(of: signature.parameterTypes[transformParameterIndex]),
                  let returnSymbol = resolveClassTypeSymbol(transformType.returnType, sema: sema)?.1
            else {
                return false
            }
            let sequenceFQName = [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                interner.intern("Sequence"),
            ]
            let iterableFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
            return returnsSequence
                ? returnSymbol.fqName == sequenceFQName
                : returnSymbol.fqName == iterableFQName
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
        requireMutableListReceiver: Bool = false) -> Bool {
        let parameterMapping = parameterMapping
            ?? Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        let typeMatches: (TypeID, TypeID) -> Bool = {
            collectionFlowTypeMatches($0, $1, types: self.sema.types)
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

    @discardableResult
    func bindBundledListBinarySearchSource() -> Bool {
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
            CallArg.source(arg, type: sema.bindings.exprTypes[arg.expr] ?? sema.types.anyType, callRange: range, ast: ctx.ast)
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
        receiverElementType: TypeID? = nil) -> Bool {
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

        let typeMatches: (TypeID, TypeID) -> Bool = {
            collectionFlowTypeMatches($0, $1, types: self.sema.types)
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

    func isComparatorTypedArgument(_ argExprID: ExprID) -> Bool {
        let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
        guard let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName),
              let argType = sema.bindings.exprType(for: argExprID),
              case let .classType(argClassType) = sema.types.kind(of: sema.types.makeNonNullable(argType))
        else {
            return false
        }
        return sema.types.isNominalSubtypeSymbol(argClassType.classSymbol, of: comparatorSymbol)
    }

    func bindBundledIterableSumSource() -> TypeID? {
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

    func bindIterableSumOfSourceForSelectorType(
        collectionElementType: TypeID,
        selectorReturnType: TypeID) -> TypeID? {
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
        ) else {
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
        allowConcreteListReceiver: Bool = false) -> Bool {
        guard !isSequenceReceiver,
              isIterableReceiver
                || (allowConcreteListReceiver && receiverClassification.isListReceiver),
              allowConcreteListReceiver || !receiverClassification.isListReceiver,
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

    func transformReturnsNonListFlattenable(
        _ returnType: TypeID,
        lambdaArgExpr: ExprID
    ) -> Bool {
        guard !receiverClassifier.isConcreteListLikeType(returnType) else {
            return false
        }
        if receiverClassifier.isIterableLikeType(returnType)
            || receiverClassifier.isSequenceLikeType(returnType)
            || MemberRuntimeDispatch.rangeReceiverKind(
                for: returnType, sema: sema, interner: interner
            ) != nil
        {
            return true
        }
        if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(lambdaArgExpr),
           sema.bindings.isRangeExpr(bodyExpr)
        {
            return true
        }
        return false
    }

    func flatMapTransformElementType(
        lambdaArgExpr: ExprID,
        returnType: TypeID
    ) -> TypeID {
        let extracted = extractIterableOrSequenceElementType(returnType, sema: sema, interner: interner)
        if extracted != sema.types.anyType {
            return extracted
        }
        if let rangeElementType = nominalRangeElementType(for: returnType, sema: sema, interner: interner) {
            return rangeElementType
        }
        if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(lambdaArgExpr),
           sema.bindings.isRangeExpr(bodyExpr)
        {
            return driver.helpers.rangeExprActualElementType(
                for: bodyExpr, bodyType: returnType, sema: sema, interner: interner
            )
        }
        return extracted
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
        guard calleeName == knownNames.asSequence else {
            return false
        }
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

    @discardableResult
    func bindBundledGenericOnEachSourceFunction(typeArguments: [TypeID]) -> Bool {
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
    func bindBundledMapIteratorSourceFunction() -> TypeID? {
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
        actualElementType: TypeID) -> Bool {
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


    func bindBundledSequenceAggregateSource(typeArguments: [TypeID], locals _: inout LocalBindings) {
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
                    )
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


    func bindBundledSequenceSumSource(locals _: inout LocalBindings) -> TypeID? {
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
                    )
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


    func bindSequenceSumOfSourceForSelectorType(
        selectorReturnType: TypeID) -> TypeID? {
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


    func bindBundledSequenceSourceIfAvailable(
        resultType: TypeID,
        otherElementType: TypeID? = nil,
        overrideTypeArguments: [TypeID]? = nil,
        allowIterableReceiver: Bool = false,
        locals _: inout LocalBindings
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
                    )
            }

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
