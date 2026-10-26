struct ContextualCallableReferenceBinding {
    let functionType: TypeID
    let typeArguments: [TypeID]
    let parameterMapping: [Int: Int]
    let requiresAdapter: Bool
    let boundContextParameterTypes: [TypeID]
    let defaultArgumentOwner: SymbolID?
}

private struct CallableReferenceFunctionShape {
    let functionType: TypeID
    let parameterMapping: [Int: Int]
    let requiresAdapter: Bool
    let isScalarVarargAdaptation: Bool
    let contextArgumentTypes: [TypeID]
    let boundContextParameterTypes: [TypeID]
}

extension TypeCheckHelpers {
    func isNominalSubtype(
        _ candidate: SymbolID,
        of base: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        if candidate == base {
            return true
        }
        var queue = symbols.directSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next == base {
                return true
            }
            if visited.insert(next).inserted {
                queue.append(contentsOf: symbols.directSupertypes(for: next))
            }
        }
        return false
    }

    func callableTargetForCalleeExpr(
        _ calleeExprID: ExprID,
        sema: SemaModule
    ) -> CallableTarget? {
        if let explicitTarget = sema.bindings.callableTarget(for: calleeExprID) {
            return explicitTarget
        }
        guard let symbol = sema.bindings.identifierSymbol(for: calleeExprID) else {
            return nil
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol) else {
            return .localValue(symbol)
        }
        if semanticSymbol.kind == .function || semanticSymbol.kind == .constructor {
            return .symbol(symbol)
        }
        return .localValue(symbol)
    }

    /// A bound member's signature is declared in terms of its owner's type
    /// parameters (`Transformer<A, B>.apply: (A) -> B`), so they are
    /// substituted with the receiver's type arguments
    /// (`Transformer<Int, Int>` -> `(Int) -> Int`) before the function type
    /// is built.
    func callableFunctionType(
        for signature: FunctionSignature,
        bindReceiver: Bool,
        boundReceiver: (symbol: SymbolID, receiverType: TypeID)? = nil,
        unboundReceiverType: TypeID? = nil,
        specializeGenericReceiver: Bool = true,
        packVarargs: Bool = true,
        targetSymbol: SymbolID? = nil,
        interner: StringInterner? = nil,
        sema: SemaModule
    ) -> TypeID {
        var params = signature.parameterTypes
        var returnType = signature.returnType
        // A top-level generic extension's own type parameters are inferred
        // from the explicit receiver, even when the surrounding expected
        // function type still contains the caller's type parameters.
        if specializeGenericReceiver,
           let boundReceiver, let declaredReceiver = signature.receiverType,
           !signature.typeParameterSymbols.isEmpty
        {
            let variables = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let resolver = OverloadResolver()
            let constraints = resolver.decomposeSubtypeConstraint(
                subtype: boundReceiver.receiverType, supertype: declaredReceiver,
                typeVarBySymbol: variables, typeSystem: sema.types, blameRange: nil
            )
            let solution = ConstraintSolver().solve(
                vars: resolver.usedTypeVariables(from: constraints), constraints: constraints,
                typeSystem: sema.types
            )
            if solution.isSuccess {
                params = params.map {
                    sema.types.substituteTypeParameters(in: $0, substitution: solution.substitution, typeVarBySymbol: variables)
                }
                returnType = sema.types.substituteTypeParameters(
                    in: returnType, substitution: solution.substitution, typeVarBySymbol: variables
                )
            }
        }
        if let boundReceiver,
           let owner = sema.symbols.parentSymbol(for: boundReceiver.symbol),
           sema.symbols.symbol(owner)?.kind == .class || sema.symbols.symbol(owner)?.kind == .interface
        {
            func specialize(_ type: TypeID) -> TypeID {
                resolveMemberPropertyType(
                    type,
                    receiverType: boundReceiver.receiverType,
                    ownerSymbol: owner,
                    sema: sema
                )
            }
            params = params.map(specialize)
            returnType = specialize(returnType)
        }
        if !bindReceiver,
           let unboundReceiverType,
           let targetSymbol,
           let owner = sema.symbols.parentSymbol(for: targetSymbol),
           sema.symbols.symbol(owner)?.kind == .class || sema.symbols.symbol(owner)?.kind == .interface
        {
            // `Comparable<Ranked>::compareTo` is an unbound member reference:
            // the receiver becomes the first function parameter, and the
            // remaining signature still needs the explicit owner's type
            // arguments. Without this substitution a stored reference keeps
            // the declaration's `T` and cannot adapt to `Comparator<Ranked>`
            // after generic inference resolves the call site.
            func specialize(_ type: TypeID) -> TypeID {
                resolveMemberPropertyType(
                    type,
                    receiverType: unboundReceiverType,
                    ownerSymbol: owner,
                    sema: sema
                )
            }
            params = params.map(specialize)
            returnType = specialize(returnType)
        }
        if packVarargs, let interner {
            for index in params.indices where signature.valueParameterIsVararg.indices.contains(index)
                && signature.valueParameterIsVararg[index] {
                // Erasure follows the declaration even when a generic receiver
                // specializes its type parameter to a primitive value.
                params[index] = primitiveVarargArrayType(
                    elementType: signature.parameterTypes[index], sema: sema, interner: interner
                ) ?? referenceVarargArrayType(elementType: params[index], sema: sema, interner: interner)
                    ?? params[index]
            }
        }
        let isAnonymous: Bool = {
            guard let targetSymbol, let name = sema.symbols.symbol(targetSymbol)?.name, let interner else {
                return false
            }
            return interner.resolve(name).hasPrefix("__AnonymousFunction_")
        }()
        if !bindReceiver, let receiverType = unboundReceiverType ?? signature.receiverType {
            if isAnonymous {
                return sema.types.make(.functionType(FunctionType(
                    contextReceivers: signature.contextParameterTypes,
                    receiver: boundReceiver?.receiverType ?? receiverType,
                    params: params,
                    returnType: returnType,
                    isSuspend: signature.isSuspend,
                    isCallableReference: false,
                    nullability: .nonNull
                )))
            }
            params.insert(boundReceiver?.receiverType ?? receiverType, at: 0)
        }
        return sema.types.make(.functionType(FunctionType(
            contextReceivers: signature.contextParameterTypes,
            params: params,
            returnType: returnType,
            isSuspend: signature.isSuspend,
            isCallableReference: !isAnonymous,
            nullability: .nonNull
        )))
    }

    /// Expression-contextual: a stored function value with a non-Unit result
    /// keeps its original type.
    func unitCoercedCallableReferenceType(
        _ callableType: TypeID,
        expectedFunctionType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        let types = sema.types
        guard case let .functionType(expectedFunction) = types.kind(of: expectedFunctionType),
              expectedFunction.returnType == types.unitType,
              case let .functionType(function) = types.kind(of: callableType),
              function.isCallableReference,
              function.returnType != types.unitType
        else {
            return nil
        }
        return types.make(.functionType(FunctionType(
            contextReceivers: function.contextReceivers,
            receiver: function.receiver,
            params: function.params,
            returnType: types.unitType,
            isSuspend: function.isSuspend,
            isCallableReference: true,
            nullability: function.nullability,
            throws: function.throws
        )))
    }

    /// Match a suspend expectation against the reference's ordinary signature
    /// before materializing its contextual adapter.
    func suspendConvertedCallableReferenceExpectedType(
        _ callableType: TypeID,
        expectedFunctionType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        let types = sema.types
        guard case let .functionType(callable) = types.kind(of: callableType),
              callable.isCallableReference,
              types.suspendConversionType(from: callableType, to: expectedFunctionType) != nil,
              case let .functionType(expected) = types.kind(of: expectedFunctionType),
              expected.isSuspend
        else {
            return nil
        }
        return types.make(.functionType(FunctionType(
            contextReceivers: expected.contextReceivers,
            receiver: expected.receiver,
            params: expected.params,
            returnType: expected.returnType,
            isSuspend: false,
            isCallableReference: expected.isCallableReference,
            nullability: expected.nullability,
            throws: expected.throws
        )))
    }

    /// Member functions record `extensionReceiverType ?? ownerType` as
    /// `signature.receiverType` (MemberHeaderCollection), so a non-nil receiver
    /// whose nominal differs from the function's own parent symbol is an
    /// extension receiver.
    /// Top-level extensions (package/nil parent) count unconditionally:
    /// Kotlin resolves them only through `Type::ext`/`obj::ext` forms and
    /// rejects a bare `::name` reference, while member-extensions are
    /// unreferenceable in every `::` form ("member and an extension at the
    /// same time").
    func declaresExtensionReceiver(_ symbolID: SymbolID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: symbolID),
              let receiverType = signature.receiverType
        else { return false }
        guard let parentID = sema.symbols.parentSymbol(for: symbolID),
              let parent = sema.symbols.symbol(parentID),
              parent.kind != .package
        else { return true }
        // Receiver attachment does not change a top-level extension's package FQ name.
        if let symbol = sema.symbols.symbol(symbolID),
           symbol.flags.contains(.extensionMemberAlias)
               || Array(symbol.fqName.dropLast()) != parent.fqName
        {
            return true
        }
        let receiverNominals = allNominalSymbols(
            of: receiverType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner
        )
        if receiverNominals.contains(parentID) {
            return false
        }
        // Builtin nominal shells can be recreated under a fresh SymbolID while
        // bundled sources are collected; compare FQ identity as well before
        // concluding the receiver is foreign to the declaring owner.
        let parentFQName = parent.fqName
        return !parentFQName.isEmpty
            && !receiverNominals.contains(where: {
                sema.symbols.symbol($0)?.fqName == parentFQName
            })
    }

    func chooseCallableReferenceTarget(
        from candidates: [SymbolID],
        expectedType: TypeID?,
        bindReceiver: Bool,
        boundReceiverType: TypeID? = nil,
        unboundReceiverType: TypeID? = nil,
        expectedCallableReferenceReturnType: TypeID? = nil,
        postponedReturnTypeParameter: SymbolID? = nil,
        interner: StringInterner? = nil,
        availableContextReceiverTypes: [TypeID] = [],
        sema: SemaModule
    ) -> SymbolID? {
        let sorted = candidates.sorted(by: { $0.rawValue < $1.rawValue })
        guard !sorted.isEmpty else {
            return nil
        }
        guard let expectedType else {
            // Without a contextual type, declaration order cannot disambiguate
            // overloaded callable references.
            return sorted.count == 1 ? sorted[0] : nil
        }

        let expectedFunctionType: TypeID? = if case .functionType = sema.types.kind(of: expectedType) {
            expectedType
        } else if let samFT = samFunctionType(for: expectedType, sema: sema) {
            sema.types.make(.functionType(samFT))
        } else {
            nil
        }
        guard let expectedFunctionType else {
            guard let expectedCallableReferenceReturnType else {
                // A non-callable expected type (for example Any?) does not
                // select one member of an overload set.
                return sorted.count == 1 ? sorted[0] : nil
            }
            let matching = sorted.filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return contextualCallableReferenceBinding(
                    for: signature,
                    targetSymbol: symbolID,
                    bindReceiver: bindReceiver,
                    boundReceiver: boundReceiverType.map { (symbolID, $0) },
                    unboundReceiverType: unboundReceiverType,
                    expectedFunctionType: nil,
                    expectedCallableReferenceReturnType: expectedCallableReferenceReturnType,
                    interner: interner,
                    availableContextReceiverTypes: availableContextReceiverTypes,
                    sema: sema
                ) != nil
            }
            if matching.count == 1 { return matching[0] }
            return matching.isEmpty && sorted.count == 1 ? sorted[0] : nil
        }
        guard case let .functionType(expectedFunction) = sema.types.kind(of: expectedFunctionType) else {
            return nil
        }
        // A generic HOF's output (e.g. R in T.let) is inferred from the
        // reference, but its specialized inputs already select an overload.
        let matchingExpectedType = sema.types.typeContainsAnyTypeParam(expectedFunction.returnType)
            ? sema.types.make(.functionType(FunctionType(
                contextReceivers: expectedFunction.contextReceivers,
                receiver: expectedFunction.receiver,
                params: expectedFunction.params,
                returnType: sema.types.nullableAnyType,
                isSuspend: expectedFunction.isSuspend,
                isCallableReference: expectedFunction.isCallableReference,
                nullability: expectedFunction.nullability,
                throws: expectedFunction.throws
            )))
            : expectedFunctionType
        func matches(_ expected: TypeID) -> [SymbolID] {
            sorted.filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return contextualCallableReferenceBinding(
                    for: signature,
                    targetSymbol: symbolID,
                    bindReceiver: bindReceiver,
                    boundReceiver: boundReceiverType.map { (symbolID, $0) },
                    unboundReceiverType: unboundReceiverType,
                    expectedFunctionType: expected,
                    postponedReturnTypeParameter: postponedReturnTypeParameter,
                    interner: interner,
                    availableContextReceiverTypes: availableContextReceiverTypes,
                    sema: sema
                ) != nil
            }
        }
        // Preserve matches against rigid outer parameters and structured
        // return types before relaxing an output still awaiting call inference.
        let contextualMatches = matches(expectedFunctionType)
        let matching = contextualMatches.isEmpty && matchingExpectedType != expectedFunctionType
            ? matches(matchingExpectedType) : contextualMatches
        func isAdapter(_ symbolID: SymbolID) -> Bool {
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return contextualCallableReferenceBinding(
                for: signature,
                targetSymbol: symbolID,
                bindReceiver: bindReceiver,
                boundReceiver: boundReceiverType.map { (symbolID, $0) },
                unboundReceiverType: unboundReceiverType,
                expectedFunctionType: expectedFunctionType,
                postponedReturnTypeParameter: postponedReturnTypeParameter,
                interner: interner,
                availableContextReceiverTypes: availableContextReceiverTypes,
                sema: sema
            )?.requiresAdapter == true
        }
        if let matched = matching.first(where: {
            !isAdapter($0) && sema.symbols.functionSignature(for: $0)?.typeParameterSymbols.isEmpty == true
        }) ?? matching.first(where: { !isAdapter($0) }) ?? matching.first(where: {
            sema.symbols.functionSignature(for: $0)?.typeParameterSymbols.isEmpty == true
        }) ?? matching.first {
            return matched
        }
        // A unique reference can supply an otherwise unknown input type to
        // call inference. Multiple incompatible references must not be fixed
        // by declaration order, nor may a concrete signature mismatch succeed.
        let hasUnresolvedInput = expectedFunction.params.contains {
            sema.types.typeContainsAnyTypeParam($0)
        } || (expectedFunction.receiver.map { sema.types.typeContainsAnyTypeParam($0) } ?? false)
        // A single reified target still needs its contextual specialization
        // check so incompatible shapes retain the dedicated inference diagnostic.
        let singleReifiedTarget = sorted.count == 1 && sorted.first.flatMap {
            sema.symbols.functionSignature(for: $0)
        }.map { !$0.reifiedTypeParameterIndices.isEmpty } == true
        return sorted.count == 1 && (hasUnresolvedInput || singleReifiedTarget) ? sorted.first : nil
    }

    func contextualCallableFunctionType(
        for signature: FunctionSignature,
        targetSymbol: SymbolID? = nil,
        bindReceiver: Bool,
        boundReceiver: (symbol: SymbolID, receiverType: TypeID)? = nil,
        unboundReceiverType: TypeID? = nil,
        expectedFunctionType: TypeID,
        interner: StringInterner? = nil,
        allowScalarVarargAdaptation: Bool = true,
        availableContextReceiverTypes: [TypeID] = [],
        sema: SemaModule
    ) -> TypeID? {
        contextualCallableReferenceBinding(
            for: signature, targetSymbol: targetSymbol, bindReceiver: bindReceiver, boundReceiver: boundReceiver,
            unboundReceiverType: unboundReceiverType,
            expectedFunctionType: expectedFunctionType, interner: interner,
            allowScalarVarargAdaptation: allowScalarVarargAdaptation,
            availableContextReceiverTypes: availableContextReceiverTypes, sema: sema
        )?.functionType
    }

    func contextualCallableReferenceBinding(
        for signature: FunctionSignature,
        targetSymbol: SymbolID? = nil,
        bindReceiver: Bool,
        boundReceiver: (symbol: SymbolID, receiverType: TypeID)? = nil,
        unboundReceiverType: TypeID? = nil,
        expectedFunctionType: TypeID?,
        expectedCallableReferenceReturnType: TypeID? = nil,
        postponedReturnTypeParameter: SymbolID? = nil,
        interner: StringInterner? = nil,
        allowScalarVarargAdaptation: Bool = true,
        availableContextReceiverTypes: [TypeID] = [],
        sema: SemaModule
    ) -> ContextualCallableReferenceBinding? {
        let defaultArgumentOwner = (targetSymbol ?? boundReceiver?.symbol).flatMap { target in
            let inheritedOwner = (boundReceiver?.receiverType ?? unboundReceiverType).flatMap {
                sema.symbols.inheritedDefaultsOwner(for: target, receiver: sema.types.makeNonNullable($0))
            }
            return inheritedOwner ?? sema.symbols.expectActualDefaultArgumentOwner(for: target)
        }
        func functionShapes() -> [CallableReferenceFunctionShape] {
            let callableType = callableFunctionType(
                for: signature,
                bindReceiver: bindReceiver,
                boundReceiver: boundReceiver,
                unboundReceiverType: unboundReceiverType,
                specializeGenericReceiver: false,
                packVarargs: false,
                targetSymbol: targetSymbol,
                interner: interner,
                sema: sema
            )
            guard let expectedFunctionType,
                  case let .functionType(expected) = sema.types.kind(of: expectedFunctionType),
                  case let .functionType(base) = sema.types.kind(of: callableType)
            else {
                let packedCallableType = callableFunctionType(
                    for: signature,
                    bindReceiver: bindReceiver,
                    boundReceiver: boundReceiver,
                    unboundReceiverType: unboundReceiverType,
                    specializeGenericReceiver: false,
                    packVarargs: true,
                    targetSymbol: targetSymbol,
                    interner: interner,
                    sema: sema
                )
                return [CallableReferenceFunctionShape(
                    functionType: packedCallableType,
                    parameterMapping: Dictionary(uniqueKeysWithValues: signature.parameterTypes.indices.map { ($0, $0) }),
                    requiresAdapter: false,
                    isScalarVarargAdaptation: false,
                    contextArgumentTypes: [],
                    boundContextParameterTypes: []
                )]
            }

            let types = sema.types
            let isAnonymousExtension: Bool = {
                guard let targetSymbol, let name = sema.symbols.symbol(targetSymbol)?.name, let interner else {
                    return false
                }
                return interner.resolve(name).hasPrefix("__AnonymousFunction_")
            }()
            let receiverOffset = !bindReceiver && (unboundReceiverType != nil || signature.receiverType != nil) && !isAnonymousExtension ? 1 : 0
            let expectedArity = (expected.receiver == nil ? 0 : 1) + expected.params.count
            let expectedValueArity = isAnonymousExtension ? expected.params.count : (expectedArity - receiverOffset)
            guard expectedValueArity >= 0 else { return [] }
            let parameterCount = signature.parameterTypes.count
            var contextBindingChoices: [[TypeID]] = [[]]
            if expected.contextReceivers.isEmpty, !base.contextReceivers.isEmpty {
                for requiredType in base.contextReceivers {
                    let matchingTypes = availableContextReceiverTypes.filter { availableType in
                        types.typeContainsAnyTypeParam(requiredType)
                            || types.isSubtype(
                                types.makeNonNullable(availableType),
                                types.makeNonNullable(requiredType)
                            )
                    }
                    if matchingTypes.isEmpty {
                        contextBindingChoices = []
                        break
                    }
                    contextBindingChoices = contextBindingChoices.flatMap { prefix in
                        matchingTypes.map { prefix + [$0] }
                    }
                }
            }
            let hasDefaults = OverloadResolver.normalizeFlags(
                defaultArgumentOwner.flatMap { sema.symbols.functionSignature(for: $0)?.valueParameterHasDefaultValues }
                    ?? signature.valueParameterHasDefaultValues,
                count: parameterCount
            )
            let isVararg = OverloadResolver.normalizeFlags(signature.valueParameterIsVararg, count: parameterCount)
            func canOmitTrailingParameters(from firstIndex: Int) -> Bool {
                guard (0 ... parameterCount).contains(firstIndex) else { return false }
                return (firstIndex ..< parameterCount).allSatisfy { hasDefaults[$0] || isVararg[$0] }
            }
            func makeShape(
                sourceParameterCount: Int,
                scalarVarargCount: Int? = nil,
                contextArgumentTypes: [TypeID] = []
            ) -> CallableReferenceFunctionShape {
                var params = Array(base.params.prefix(receiverOffset + sourceParameterCount))
                var mapping = Dictionary(uniqueKeysWithValues: (0 ..< sourceParameterCount).map { ($0, $0) })
                if let scalarVarargCount,
                   let varargIndex = isVararg.firstIndex(of: true)
                {
                    let scalarType = base.params[receiverOffset + varargIndex]
                    params = Array(base.params.prefix(receiverOffset + varargIndex))
                        + Array(repeating: scalarType, count: scalarVarargCount)
                    mapping = Dictionary(uniqueKeysWithValues: (0 ..< varargIndex).map { ($0, $0) })
                    for argumentIndex in varargIndex ..< varargIndex + scalarVarargCount {
                        mapping[argumentIndex] = varargIndex
                    }
                } else if let varargIndex = isVararg.firstIndex(of: true), varargIndex < sourceParameterCount {
                    let index = receiverOffset + varargIndex
                    let elementType = base.params[index]
                    if let interner {
                        params[index] = primitiveVarargArrayType(
                            elementType: signature.parameterTypes[varargIndex], sema: sema, interner: interner
                        ) ?? referenceVarargArrayType(elementType: elementType, sema: sema, interner: interner)
                            ?? elementType
                    }
                }
                var requiresErasedPrimitiveInputAdapter = false
                if case let .functionType(expectedFunction) = types.kind(of: expectedFunctionType) {
                    let expectedInputs = (expectedFunction.receiver.map { [$0] } ?? []) + expectedFunction.params
                    for sourceParameterIndex in 0 ..< sourceParameterCount {
                        let shapeIndex = receiverOffset + sourceParameterIndex
                        let expectedIndex = receiverOffset + sourceParameterIndex
                        guard params.indices.contains(shapeIndex),
                              expectedInputs.indices.contains(expectedIndex)
                        else {
                            continue
                        }
                        let expectedType = expectedInputs[expectedIndex]
                        let targetKind = types.kind(of: types.makeNonNullable(params[shapeIndex]))
                        let expectedKind = types.kind(of: types.makeNonNullable(expectedType))
                        let targetIsErased: Bool = switch targetKind {
                        case .any, .typeParam: true
                        default: false
                        }
                        guard targetIsErased, case .primitive = expectedKind else { continue }
                        // A contravariant reference from an erased parameter to
                        // a primitive input needs a wrapper so the input is
                        // boxed before the referenced function receives it.
                        params[shapeIndex] = expectedType
                        requiresErasedPrimitiveInputAdapter = true
                    }
                }
                let functionType = types.make(.functionType(FunctionType(
                    contextReceivers: contextArgumentTypes.isEmpty ? base.contextReceivers : [],
                    receiver: base.receiver,
                    params: params,
                    returnType: base.returnType,
                    isSuspend: base.isSuspend,
                    isCallableReference: base.isCallableReference,
                    nullability: base.nullability,
                    throws: base.throws
                )))
                return CallableReferenceFunctionShape(
                    functionType: functionType,
                    parameterMapping: mapping,
                    requiresAdapter: scalarVarargCount != nil || sourceParameterCount != parameterCount
                        || !contextArgumentTypes.isEmpty || requiresErasedPrimitiveInputAdapter,
                    isScalarVarargAdaptation: scalarVarargCount != nil,
                    contextArgumentTypes: contextArgumentTypes,
                    boundContextParameterTypes: contextArgumentTypes.isEmpty ? [] : base.contextReceivers
                )
            }

            guard let varargIndex = isVararg.firstIndex(of: true) else {
                guard expectedValueArity <= parameterCount,
                      canOmitTrailingParameters(from: expectedValueArity)
                else { return [] }
                return contextBindingChoices.map {
                    makeShape(sourceParameterCount: expectedValueArity, contextArgumentTypes: $0)
                }
            }

            var shapes: [CallableReferenceFunctionShape] = []
            if expectedValueArity <= parameterCount,
               canOmitTrailingParameters(from: expectedValueArity)
            {
                shapes.append(contentsOf: contextBindingChoices.map {
                    makeShape(sourceParameterCount: expectedValueArity, contextArgumentTypes: $0)
                })
            }
            guard allowScalarVarargAdaptation,
                  expectedValueArity > varargIndex,
                  (varargIndex + 1 ..< parameterCount).allSatisfy({ hasDefaults[$0] })
            else { return shapes }

            let expectedInputs = (expected.receiver.map { [$0] } ?? []) + expected.params
            let expectedVarargIndex = receiverOffset + varargIndex
            let arrayShapedVarargContext: Bool = if let interner,
                                                    expectedInputs.indices.contains(expectedVarargIndex),
                                                    case let .classType(arrayType) = types.kind(of: types.makeNonNullable(
                                                        expectedInputs[expectedVarargIndex]
                                                    )),
                                                    let arraySymbol = sema.symbols.symbol(arrayType.classSymbol)
            {
                arraySymbol.fqName.map(interner.resolve) == ["kotlin", "Array"]
            } else {
                false
            }
            guard !arrayShapedVarargContext else { return shapes }
            shapes.append(contentsOf: contextBindingChoices.map {
                makeShape(
                    sourceParameterCount: expectedValueArity,
                    scalarVarargCount: expectedValueArity - varargIndex,
                    contextArgumentTypes: $0
                )
            })
            return shapes
        }

        func attempt(shape: CallableReferenceFunctionShape) -> ContextualCallableReferenceBinding? {
            let callableType = shape.functionType
            let inferredType = expectedFunctionType.flatMap { expected in
                unitCoercedCallableReferenceType(callableType, expectedFunctionType: expected, sema: sema)
            } ?? callableType
            let types = sema.types
            let constraintExpectedFunctionType = expectedFunctionType.flatMap { expected in
                suspendConvertedCallableReferenceExpectedType(
                    inferredType, expectedFunctionType: expected, sema: sema
                )
            } ?? expectedFunctionType
            let typeVars = types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            guard !typeVars.isEmpty else {
                guard callableReferenceTypeMatches(
                    inferredType,
                    expected: expectedFunctionType,
                    expectedCallableReferenceReturnType: expectedCallableReferenceReturnType,
                    postponedReturn: postponedReturnTypeParameter,
                    deferScalarVarargInputTypeParameters: shape.isScalarVarargAdaptation,
                    sema: sema
                ) else { return nil }
                return ContextualCallableReferenceBinding(
                    functionType: inferredType,
                    typeArguments: [],
                    parameterMapping: shape.parameterMapping,
                    requiresAdapter: shape.requiresAdapter,
                    boundContextParameterTypes: shape.boundContextParameterTypes,
                    defaultArgumentOwner: defaultArgumentOwner
                )
            }
            let resolver = OverloadResolver()
            var constraints: [VariableConstraint]
            if let postponedReturnTypeParameter {
                guard let expectedFunctionType,
                      case let .functionType(actual) = types.kind(of: inferredType),
                      case let .functionType(expected) = types.kind(of: expectedFunctionType),
                      case let .typeParam(resultParameter) = types.kind(of: expected.returnType),
                      resultParameter.symbol == postponedReturnTypeParameter else { return nil }
                let actualInputs = (actual.receiver.map { [$0] } ?? []) + actual.params
                let expectedInputs = (expected.receiver.map { [$0] } ?? []) + expected.params
                guard actualInputs.count == expectedInputs.count,
                      actual.contextReceivers.count == expected.contextReceivers.count,
                      expected.isSuspend || !actual.isSuspend,
                      actual.nullability == expected.nullability || expected.nullability == .nullable,
                      !(expectedInputs + expected.contextReceivers).contains(where: {
                          types.typeContainsTypeParam($0, symbol: postponedReturnTypeParameter)
                      }) else { return nil }
                // Only the caller's direct return leaf is postponed. Preserve all
                // known shape/input constraints and do not invent return evidence.
                constraints = zip(expectedInputs + expected.contextReceivers,
                                  actualInputs + actual.contextReceivers).flatMap {
                    resolver.decomposeSubtypeConstraint(
                        subtype: $0.0, supertype: $0.1, typeVarBySymbol: typeVars,
                        typeSystem: types, blameRange: nil
                    )
                }
            } else if let expectedFunctionType {
                constraints = resolver.decomposeSubtypeConstraint(
                    subtype: inferredType, supertype: constraintExpectedFunctionType ?? expectedFunctionType,
                    typeVarBySymbol: typeVars, typeSystem: types, blameRange: nil
                )
            } else if let expectedCallableReferenceReturnType,
                      case let .functionType(actual) = types.kind(of: inferredType)
            {
                constraints = resolver.decomposeSubtypeConstraint(
                    subtype: actual.returnType,
                    supertype: expectedCallableReferenceReturnType,
                    typeVarBySymbol: typeVars,
                    typeSystem: types,
                    blameRange: nil
                )
            } else { constraints = [] }
            for (actualType, requiredType) in zip(
                shape.contextArgumentTypes, shape.boundContextParameterTypes
            ) {
                constraints += resolver.decomposeSubtypeConstraint(
                    subtype: actualType,
                    supertype: requiredType,
                    typeVarBySymbol: typeVars,
                    typeSystem: types,
                    blameRange: nil
                )
            }
            if let boundReceiver, let receiverType = signature.receiverType {
                constraints += resolver.decomposeSubtypeConstraint(
                    subtype: boundReceiver.receiverType,
                    supertype: receiverType,
                    typeVarBySymbol: typeVars,
                    typeSystem: types,
                    blameRange: nil
                )
            }
            // Seed real owner slots even when their argument is the same
            // lexical T; subtype T <: T alone supplies no solver substitution.
            if let boundReceiver, let owner = sema.symbols.parentSymbol(for: boundReceiver.symbol),
               case let .classType(receiver) = types.kind(of: types.makeNonNullable(
                   types.capturedReadableUpperBound(of: boundReceiver.receiverType)
               )),
               types.isNominalSubtypeSymbol(receiver.classSymbol, of: owner),
               let ownerArgs = types.liftedNominalSupertypeArgs(
                   from: receiver.classSymbol, childArgs: receiver.args, to: owner
               ) {
                for (index, symbol) in signature.typeParameterSymbols.prefix(signature.classTypeParameterCount).enumerated() {
                    guard ownerArgs.indices.contains(index), let variable = typeVars[symbol] else { continue }
                    let parameterType = types.make(.typeParam(TypeParamType(symbol: symbol)))
                    let argument = resolveMemberPropertyType(
                        parameterType, receiverType: boundReceiver.receiverType, ownerSymbol: owner, sema: sema
                    )
                    constraints.append(VariableConstraint(kind: .equal, left: .variable(variable), right: .type(argument)))
                }
            }
            func upperBounds(_ index: Int, _ symbol: SymbolID) -> [TypeID] {
                let declared = index < signature.typeParameterUpperBoundsList.count
                    ? signature.typeParameterUpperBoundsList[index] : []
                let stored = sema.symbols.typeParameterUpperBounds(for: symbol)
                return declared + stored.filter { !declared.contains($0) }
            }
            let contextualVariables = Set(resolver.usedTypeVariables(from: constraints))
            for (index, symbol) in signature.typeParameterSymbols.enumerated() {
                guard let variable = typeVars[symbol], contextualVariables.contains(variable) else { continue }
                for bound in upperBounds(index, symbol)
                    where !resolver.containsTypeVariable(bound, typeVarBySymbol: typeVars, typeSystem: types)
                {
                    constraints.append(VariableConstraint(
                        kind: .subtype, left: .variable(variable), right: .type(bound)
                    ))
                }
            }
            var solution = ConstraintSolver().solve(
                vars: resolver.usedTypeVariables(from: constraints),
                constraints: constraints,
                typeSystem: types
            )
            // Dependent bounds can infer another parameter, e.g. C : List<T>.
            for _ in 0 ..< signature.typeParameterSymbols.count {
                guard solution.isSuccess else { return nil }
                var added = false
                for (index, symbol) in signature.typeParameterSymbols.enumerated() {
                    guard let variable = typeVars[symbol],
                          let argument = solution.substitution[variable],
                          argument != types.errorType
                    else { continue }
                    for bound in upperBounds(index, symbol) {
                        let substitutedBound = types.substituteTypeParameters(
                            in: bound, substitution: solution.substitution, typeVarBySymbol: typeVars
                        )
                        let decomposed = resolver.decomposeSubtypeConstraint(
                            subtype: argument,
                            supertype: substitutedBound,
                            typeVarBySymbol: typeVars,
                            typeSystem: types,
                            blameRange: nil
                        )
                        constraints += decomposed
                        added = added || !resolver.usedTypeVariables(from: decomposed).isEmpty
                    }
                }
                solution = ConstraintSolver().solve(
                    vars: resolver.usedTypeVariables(from: constraints),
                    constraints: constraints,
                    typeSystem: types
                )
                if !added { break }
            }
            guard solution.isSuccess else { return nil }
            for (index, symbol) in signature.typeParameterSymbols.enumerated() {
                guard let variable = typeVars[symbol],
                      let argument = solution.substitution[variable],
                      argument != types.errorType
                else {
                    return nil
                }
                for bound in upperBounds(index, symbol) {
                    let substitutedBound = types.substituteTypeParameters(
                        in: bound, substitution: solution.substitution, typeVarBySymbol: typeVars
                    )
                    guard types.isSubtype(argument, substitutedBound) else { return nil }
                }
            }
            let specializedType = types.substituteTypeParameters(
                in: inferredType, substitution: solution.substitution, typeVarBySymbol: typeVars
            )
            let specializedContextTypes = shape.boundContextParameterTypes.map {
                types.substituteTypeParameters(
                    in: $0, substitution: solution.substitution, typeVarBySymbol: typeVars
                )
            }
            guard zip(shape.contextArgumentTypes, specializedContextTypes).allSatisfy({ actualType, requiredType in
                types.isSubtype(
                    types.makeNonNullable(actualType),
                    types.makeNonNullable(requiredType)
                )
            }) else { return nil }
            guard callableReferenceTypeMatches(
                specializedType, expected: expectedFunctionType,
                expectedCallableReferenceReturnType: expectedCallableReferenceReturnType,
                postponedReturn: postponedReturnTypeParameter,
                deferScalarVarargInputTypeParameters: shape.isScalarVarargAdaptation,
                sema: sema
            ) else { return nil }
            var arguments: [TypeID] = []
            for symbol in signature.typeParameterSymbols {
                guard let variable = typeVars[symbol], let argument = solution.substitution[variable] else { return nil }
                arguments.append(argument)
            }
            return ContextualCallableReferenceBinding(
                functionType: specializedType,
                typeArguments: arguments,
                parameterMapping: shape.parameterMapping,
                requiresAdapter: shape.requiresAdapter,
                boundContextParameterTypes: specializedContextTypes,
                defaultArgumentOwner: defaultArgumentOwner
            )
        }
        for shape in functionShapes() {
            if let result = attempt(shape: shape) { return result }
        }
        return nil
    }

    private func callableReferenceTypeMatches(
        _ actualType: TypeID,
        expected: TypeID?,
        expectedCallableReferenceReturnType: TypeID? = nil,
        postponedReturn: SymbolID?,
        deferScalarVarargInputTypeParameters: Bool = false,
        sema: SemaModule
    ) -> Bool {
        if let expectedCallableReferenceReturnType {
            guard case let .functionType(actual) = sema.types.kind(of: actualType),
                  sema.types.isSubtype(actual.returnType, expectedCallableReferenceReturnType)
            else { return false }
        }
        guard let expected else { return true }
        var matchingExpected = suspendConvertedCallableReferenceExpectedType(
            actualType, expectedFunctionType: expected, sema: sema
        ) ?? expected
        if deferScalarVarargInputTypeParameters,
           case let .functionType(actual) = sema.types.kind(of: actualType),
           case let .functionType(context) = sema.types.kind(of: matchingExpected)
        {
            let actualInputs = (actual.receiver.map { [$0] } ?? []) + actual.params
            var expectedInputs = (context.receiver.map { [$0] } ?? []) + context.params
            guard actualInputs.count == expectedInputs.count else { return false }
            var deferredInput = false
            for index in expectedInputs.indices where sema.types.typeContainsAnyTypeParam(expectedInputs[index]) {
                expectedInputs[index] = actualInputs[index]
                deferredInput = true
            }
            if deferredInput {
                let receiverCount = context.receiver == nil ? 0 : 1
                let deferredExpected = sema.types.make(.functionType(FunctionType(
                    contextReceivers: context.contextReceivers,
                    receiver: receiverCount == 0 ? nil : expectedInputs.first,
                    params: Array(expectedInputs.dropFirst(receiverCount)),
                    returnType: context.returnType,
                    isSuspend: context.isSuspend,
                    isCallableReference: context.isCallableReference,
                    nullability: context.nullability,
                    throws: context.throws
                )))
                matchingExpected = deferredExpected
            }
        }
        guard let postponedReturn,
              case let .functionType(actual) = sema.types.kind(of: actualType),
              case let .functionType(context) = sema.types.kind(of: matchingExpected),
              case let .typeParam(parameter) = sema.types.kind(of: context.returnType),
              parameter.symbol == postponedReturn
        else { return sema.types.isSubtype(actualType, matchingExpected) }
        for bound in sema.symbols.typeParameterUpperBounds(for: postponedReturn)
            where !sema.types.typeContainsAnyTypeParam(bound) {
            let resultBound = parameter.nullability == .nullable ? sema.types.makeNullable(bound) : bound
            guard sema.types.isSubtype(actual.returnType, resultBound) else { return false }
        }
        let comparison = sema.types.make(.functionType(FunctionType(
            contextReceivers: context.contextReceivers, receiver: context.receiver,
            params: context.params, returnType: actual.returnType,
            isSuspend: context.isSuspend, isCallableReference: context.isCallableReference,
            nullability: context.nullability, throws: context.throws
        )))
        return sema.types.isSubtype(actualType, comparison)
    }

    func reflectiveCallableReferenceReturnType(
        from expectedType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        guard let kFunctionSymbol = sema.types.kFunctionInterfaceSymbol,
              case let .classType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
              functionType.classSymbol == kFunctionSymbol,
              functionType.args.count == 1
        else { return nil }
        switch functionType.args[0] {
        case let .invariant(type), let .out(type): return type
        case .in, .star: return nil
        }
    }

}
