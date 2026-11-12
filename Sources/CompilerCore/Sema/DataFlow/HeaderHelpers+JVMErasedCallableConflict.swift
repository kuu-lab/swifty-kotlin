
extension DataFlowSemaPhase {
    /// A user-declared top-level `fun X(...)` whose value-parameter signature
    /// matches a constructor of a user-declared class `X` in the same package
    /// is a redeclaration (kotlinc: conflicting declarations). Factory-style
    /// functions with a different signature (e.g. `fun Random(seed: Long)`)
    /// stay legal. Called from both the class-constructor and the function
    /// header paths; only the later of the two sees both signatures.
    func checkAndReportClassConstructorFunctionConflict(
        classFQName: [InternedString],
        range: SourceRange?,
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        isJVMTarget: Bool
    ) {
        // kotlinc exempts @LowPriorityInOverloadResolution declarations from
        // the redeclaration check: overload resolution already orders them
        // below the regular-priority one, so the pair is not ambiguous.
        func isLowPriority(_ id: SymbolID) -> Bool {
            symbols.annotations(for: id).contains {
                $0.annotationFQName == KnownCompilerAnnotation.lowPriorityInOverloadResolution.qualifiedName
            }
        }
        func isUserSource(_ id: SymbolID) -> Bool {
            // Constructors carry no source file ID of their own; use their owner's.
            guard let fileID = symbols.sourceFileID(for: id)
                ?? symbols.parentSymbol(for: id).flatMap({ symbols.sourceFileID(for: $0) })
            else { return false }
            return sourceManager.origin(of: fileID)?.isBundledStdlib != true
        }
        let constructors = symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).compactMap { id -> FunctionSignature? in
            guard let symbol = symbols.symbol(id), symbol.kind == .constructor,
                  !symbol.flags.contains(.synthetic), isUserSource(id), !isLowPriority(id),
                  let signature = symbols.functionSignature(for: id)
            else { return nil }
            // A constructor's receiver is the class it constructs; a
            // conflicting top-level function is receiverless, so the receiver
            // must be stripped before signature comparison.
            return FunctionSignature(
                contextReceiverTypes: signature.contextReceiverTypes,
                contextParameterSymbols: signature.contextParameterSymbols,
                contextParameterTypes: signature.contextParameterTypes,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                canThrow: signature.canThrow,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterUnsafeVarianceTypeParameterSymbols: signature.valueParameterUnsafeVarianceTypeParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
                hasStableParameterNames: signature.hasStableParameterNames,
                typeParameterSymbols: signature.typeParameterSymbols,
                reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBounds: signature.typeParameterUpperBounds,
                typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                classTypeParameterCount: signature.classTypeParameterCount
            )
        }
        guard !constructors.isEmpty else { return }
        // A constructor's implicit class receiver is not part of the callable
        // signature a same-named top-level function must match — comparing it
        // against the function's absent receiver would mask the conflict.
        let constructorSignatures = constructors.map { $0.replacingReceiverType(nil) }
        let hasConflict = symbols.lookupAll(fqName: classFQName).contains { id in
            guard let symbol = symbols.symbol(id), symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.expectDeclaration), !symbol.flags.contains(.actualDeclaration),
                  symbols.parentSymbol(for: id) == nil, isUserSource(id), !isLowPriority(id),
                  let signature = symbols.functionSignature(for: id),
                  signature.receiverType == nil,
                  signature.contextReceiverTypes.isEmpty,
                  signature.contextParameterTypes.isEmpty
            else { return false }
            return constructorSignatures.contains { constructor in
                hasSameSourceCallableSignature(signature, constructor, types: types)
                    || isJVMTarget && hasSameJVMErasedCallableSignature(
                        signature,
                        constructor,
                        types: types
                    )
            }
        }
        if hasConflict {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Conflicting declarations: class constructor and top-level function with the same signature.",
                range: range
            )
        }
    }

    func checkAndReportJVMErasedCallableConflict(
        for symbol: SymbolID,
        fqName: [InternedString],
        range: SourceRange?,
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        isJVMTarget: Bool
    ) {
        guard let newSymbol = symbols.symbol(symbol),
              newSymbol.kind == .function,
              let newSignature = symbols.functionSignature(for: symbol)
        else {
            return
        }

        let hasConflict = symbols.lookupAll(fqName: fqName).contains { existingID in
            guard existingID != symbol,
                  let existingSymbol = symbols.symbol(existingID),
                  existingSymbol.kind == newSymbol.kind,
                  !canCoexistAsExpectActualPair(newSymbol, existingSymbol),
                  !canCoexistAsSyntheticFallback(newSymbol, existingSymbol),
                  !canCoexistAsPrivateTopLevelCallableAcrossSourceFiles(
                      newSymbol,
                      existingSymbol,
                      symbols: symbols
                  ),
                  let existingSignature = symbols.functionSignature(for: existingID)
            else {
                return false
            }
            if isJVMTarget {
                return hasSameJVMErasedCallableSignature(newSignature, existingSignature, types: types)
            }
            guard !newSymbol.flags.contains(.importedLibrary),
                  !existingSymbol.flags.contains(.importedLibrary),
                  !isBundledStdlibSource(symbol, symbols: symbols, sourceManager: sourceManager),
                  !isBundledStdlibSource(existingID, symbols: symbols, sourceManager: sourceManager)
            else {
                return false
            }
            // A dispatch receiver's nullability is not part of the callable
            // identity, so `String.f` and `String?.f` still collide even
            // though nullable value-parameter overloads stay legal on
            // non-JVM targets (KUU-3750).
            return hasSameSourceCallableSignature(
                newSignature.replacingReceiverType(newSignature.receiverType.map {
                    jvmErasedCallableType($0, types: types)
                }),
                existingSignature.replacingReceiverType(existingSignature.receiverType.map {
                    jvmErasedCallableType($0, types: types)
                }),
                types: types
            )
        }

        if hasConflict {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                isJVMTarget
                    ? "Duplicate JVM-erased callable declaration in the same package scope."
                    : "Conflicting overloads: callable declarations have the same signature in the same package scope.",
                range: range
            )
        }
    }

    private func isBundledStdlibSource(
        _ symbol: SymbolID,
        symbols: SymbolTable,
        sourceManager: SourceManager
    ) -> Bool {
        guard let fileID = symbols.sourceFileID(for: symbol) else { return false }
        return sourceManager.origin(of: fileID)?.isBundledStdlib == true
    }

    private func canCoexistAsPrivateTopLevelCallableAcrossSourceFiles(
        _ lhs: SemanticSymbol,
        _ rhs: SemanticSymbol,
        symbols: SymbolTable
    ) -> Bool {
        // Kotlin private top-level callables are file-scoped, so distinct source
        // files compile them into distinct JVM file facades.
        guard lhs.visibility == .private,
              rhs.visibility == .private,
              symbols.parentSymbol(for: lhs.id) == nil,
              symbols.parentSymbol(for: rhs.id) == nil,
              let lhsFileID = symbols.sourceFileID(for: lhs.id),
              let rhsFileID = symbols.sourceFileID(for: rhs.id)
        else {
            return false
        }
        return lhsFileID != rhsFileID
    }

    func hasSameJVMErasedCallableSignature(
        _ lhs: FunctionSignature,
        _ rhs: FunctionSignature,
        types: TypeSystem
    ) -> Bool {
        guard lhs.isSuspend == rhs.isSuspend else { return false }
        func erasedParameterTypes(_ signature: FunctionSignature) -> [TypeID] {
            let receiver = signature.receiverType.map { [$0] } ?? []
            return receiver + signature.contextReceiverTypes + signature.contextParameterTypes
                + signature.parameterTypes
        }
        func varargFlags(_ signature: FunctionSignature) -> [Bool] {
            let receiverAndContextCount = (signature.receiverType == nil ? 0 : 1)
                + signature.contextReceiverTypes.count + signature.contextParameterTypes.count
            return Array(repeating: false, count: receiverAndContextCount)
                + normalizedVarargFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count)
        }
        let lhsVarargs = varargFlags(lhs)
        let rhsVarargs = varargFlags(rhs)
        guard lhsVarargs == rhsVarargs else {
            return false
        }
        let lhsParameters = erasedParameterTypes(lhs).map { jvmErasedCallableType($0, types: types) }
        let rhsParameters = erasedParameterTypes(rhs).map { jvmErasedCallableType($0, types: types) }
        return zip(lhsParameters, rhsParameters).allSatisfy(==)
    }

    func hasSameSourceCallableSignature(
        _ lhs: FunctionSignature,
        _ rhs: FunctionSignature,
        types: TypeSystem
    ) -> Bool {
        guard lhs.isSuspend == rhs.isSuspend,
              lhs.typeParameterSymbols.count == rhs.typeParameterSymbols.count,
              lhs.contextReceiverTypes.count == rhs.contextReceiverTypes.count,
              lhs.contextParameterTypes.count == rhs.contextParameterTypes.count,
              lhs.parameterTypes.count == rhs.parameterTypes.count,
              normalizedVarargFlags(lhs.valueParameterIsVararg, count: lhs.parameterTypes.count)
                  == normalizedVarargFlags(rhs.valueParameterIsVararg, count: rhs.parameterTypes.count)
        else {
            return false
        }

        let lhsTypeParameterIndices = Dictionary(uniqueKeysWithValues: lhs.typeParameterSymbols.enumerated().map {
            ($0.element, $0.offset)
        })
        let rhsTypeParameterIndices = Dictionary(uniqueKeysWithValues: rhs.typeParameterSymbols.enumerated().map {
            ($0.element, $0.offset)
        })

        func equivalentTypes(_ left: [TypeID], _ right: [TypeID]) -> Bool {
            left.count == right.count && zip(left, right).allSatisfy { equivalent($0.0, $0.1) }
        }

        func equivalentTypeArguments(_ left: [TypeArg], _ right: [TypeArg]) -> Bool {
            guard left.count == right.count else { return false }
            return zip(left, right).allSatisfy { leftArgument, rightArgument in
                switch (leftArgument, rightArgument) {
                case let (.invariant(leftType), .invariant(rightType)),
                     let (.out(leftType), .out(rightType)),
                     let (.in(leftType), .in(rightType)):
                    equivalent(leftType, rightType)
                case (.star, .star):
                    true
                default:
                    false
                }
            }
        }

        func equivalent(_ left: TypeID, _ right: TypeID) -> Bool {
            switch (types.kind(of: left), types.kind(of: right)) {
            case (.error, .error), (.unit, .unit), (.nullableUnit, .nullableUnit), (.platformUnit, .platformUnit):
                return true
            case let (.nothing(leftNullability), .nothing(rightNullability)),
                 let (.any(leftNullability), .any(rightNullability)),
                 let (.stringStruct(leftNullability), .stringStruct(rightNullability)):
                return leftNullability == rightNullability
            case let (.primitive(leftType, leftNullability), .primitive(rightType, rightNullability)):
                return leftType == rightType && leftNullability == rightNullability
            case let (.typeParam(leftType), .typeParam(rightType)):
                guard leftType.nullability == rightType.nullability else { return false }
                if leftType.capture != nil || rightType.capture != nil {
                    return leftType == rightType
                }
                if let leftIndex = lhsTypeParameterIndices[leftType.symbol],
                   let rightIndex = rhsTypeParameterIndices[rightType.symbol]
                {
                    return leftIndex == rightIndex
                }
                return leftType.symbol == rightType.symbol
            case let (.classType(leftType), .classType(rightType)):
                return leftType.classSymbol == rightType.classSymbol
                    && leftType.nullability == rightType.nullability
                    && equivalentTypeArguments(leftType.args, rightType.args)
                    && equivalentTypeArguments(leftType.enclosingTypeArgs, rightType.enclosingTypeArgs)
            case let (.functionType(leftType), .functionType(rightType)):
                return leftType.isSuspend == rightType.isSuspend
                    && leftType.isCallableReference == rightType.isCallableReference
                    && leftType.nullability == rightType.nullability
                    && equivalentTypes(leftType.contextReceivers, rightType.contextReceivers)
                    && optionalTypesEquivalent(leftType.receiver, rightType.receiver)
                    && equivalentTypes(leftType.params, rightType.params)
                    && equivalent(leftType.returnType, rightType.returnType)
                    && equivalentTypes(leftType.throws, rightType.throws)
            case let (.intersection(leftParts), .intersection(rightParts)):
                return equivalentTypes(leftParts, rightParts)
            case let (.kClassType(leftType), .kClassType(rightType)):
                return leftType.nullability == rightType.nullability
                    && equivalent(leftType.argument, rightType.argument)
            default:
                return false
            }
        }

        func optionalTypesEquivalent(_ left: TypeID?, _ right: TypeID?) -> Bool {
            switch (left, right) {
            case let (left?, right?): equivalent(left, right)
            case (nil, nil): true
            default: false
            }
        }

        guard optionalTypesEquivalent(lhs.receiverType, rhs.receiverType),
              equivalentTypes(lhs.contextReceiverTypes, rhs.contextReceiverTypes),
              equivalentTypes(lhs.contextParameterTypes, rhs.contextParameterTypes),
              equivalentTypes(lhs.parameterTypes, rhs.parameterTypes)
        else { return false }

        // Type parameters that occur in the signature carry their upper
        // bounds: `Assert<T : Iterable<E>>.atLeast` and
        // `Assert<U : Sequence<E>>.atLeast` are distinct overloads on targets
        // without JVM erasure, while `<T> f(T)` and `<U : Any?> f(U)` still
        // conflict because an omitted bound means `Any?`. Bounds of type
        // parameters that never occur in the signature do not participate —
        // `<T : CharSequence> f(Int)` and `<U : Number> f(Int)` are a source
        // level conflict on every target (KUU-3961).
        func collectOccurringTypeParameterIndices(_ type: TypeID, into indices: inout Set<Int>) {
            switch types.kind(of: type) {
            case let .typeParam(typeParam):
                if let index = lhsTypeParameterIndices[typeParam.symbol] {
                    indices.insert(index)
                }
            case let .classType(classType):
                for argument in classType.args + classType.enclosingTypeArgs {
                    switch argument {
                    case let .invariant(argumentType),
                         let .out(argumentType),
                         let .in(argumentType):
                        collectOccurringTypeParameterIndices(argumentType, into: &indices)
                    case .star:
                        break
                    }
                }
            case let .functionType(functionType):
                for nested in functionType.contextReceivers
                    + (functionType.receiver.map { [$0] } ?? [])
                    + functionType.params + [functionType.returnType] + functionType.throws
                {
                    collectOccurringTypeParameterIndices(nested, into: &indices)
                }
            case let .intersection(parts):
                for part in parts {
                    collectOccurringTypeParameterIndices(part, into: &indices)
                }
            case let .kClassType(kClassType):
                collectOccurringTypeParameterIndices(kClassType.argument, into: &indices)
            default:
                break
            }
        }

        var occurringTypeParameterIndices: Set<Int> = []
        for comparedType in (lhs.receiverType.map { [$0] } ?? [])
            + lhs.contextReceiverTypes + lhs.contextParameterTypes + lhs.parameterTypes
        {
            collectOccurringTypeParameterIndices(comparedType, into: &occurringTypeParameterIndices)
        }

        func upperBounds(of signature: FunctionSignature, at index: Int) -> [TypeID] {
            guard signature.typeParameterUpperBoundsList.indices.contains(index),
                  !signature.typeParameterUpperBoundsList[index].isEmpty
            else {
                return [types.nullableAnyType]
            }
            return signature.typeParameterUpperBoundsList[index]
        }

        return occurringTypeParameterIndices.allSatisfy { index in
            let leftBounds = upperBounds(of: lhs, at: index)
            let rightBounds = upperBounds(of: rhs, at: index)
            return leftBounds.count == rightBounds.count
                && leftBounds.allSatisfy { leftBound in
                    rightBounds.contains { equivalent(leftBound, $0) }
                }
        }
    }

    private func normalizedVarargFlags(_ flags: [Bool], count: Int) -> [Bool] {
        flags.isEmpty ? Array(repeating: false, count: count) : flags
    }

    func jvmErasedCallableType(_ type: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: type) {
        case .stringStruct:
            return types.makeNonNullable(type)
        case .primitive:
            return type
        default:
            return types.makeNonNullable(type)
        }
    }

    func canCoexistAsExpectActualPair(_ lhs: SemanticSymbol, _ rhs: SemanticSymbol) -> Bool {
        guard lhs.kind == rhs.kind else {
            return false
        }

        let lhsIsExpect = lhs.flags.contains(.expectDeclaration)
        let lhsIsActual = lhs.flags.contains(.actualDeclaration)
        let rhsIsExpect = rhs.flags.contains(.expectDeclaration)
        let rhsIsActual = rhs.flags.contains(.actualDeclaration)

        guard lhsIsExpect != lhsIsActual,
              rhsIsExpect != rhsIsActual
        else {
            return false
        }

        return (lhsIsExpect && rhsIsActual) || (lhsIsActual && rhsIsExpect)
    }

    func canCoexistAsSyntheticFallback(_ lhs: SemanticSymbol, _ rhs: SemanticSymbol) -> Bool {
        lhs.flags.contains(.synthetic) != rhs.flags.contains(.synthetic)
    }
}
