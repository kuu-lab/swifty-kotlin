
extension ABILoweringPass {
    func applyArgumentBoxing(
        arguments: [KIRExprID],
        signature: FunctionSignature,
        receiverOffset: Int,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        boxingCalleeTable: BoxingCalleeTable,
        callee: InternedString?,
        interner: StringInterner,
        boxTypeParamArguments: Bool = false,
        newBody: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        var boxedArguments = arguments
        let parameterTypes = signature.parameterTypes
        let varargFlags = signature.valueParameterIsVararg
        for argIndex in arguments.indices {
            let paramIndex = argIndex - receiverOffset
            guard paramIndex >= 0, paramIndex < parameterTypes.count else {
                continue
            }
            if paramIndex < varargFlags.count, varargFlags[paramIndex] {
                continue
            }
            let paramType = parameterTypes[paramIndex]
            let argType = intrinsicArgType(arguments[argIndex], arena: module.arena, types: types)
            guard let argType else {
                continue
            }
            if let boxCallee = boxingCallee(
                argType: argType,
                paramType: paramType,
                callee: callee,
                types: types,
                interner: interner,
                boxingCalleeTable: boxingCalleeTable,
                symbols: symbols,
                boxTypeParamBoundary: boxTypeParamArguments,
                preferStaticPrimitive: true
            ) {
                let boxedResult = module.arena.appendTemporary(type: paramType)
                emitBoxCallWithValueClassTag(
                    boxCallee: boxCallee,
                    value: arguments[argIndex],
                    rawSourceKind: types.kind(of: argType),
                    result: boxedResult,
                    resultType: paramType,
                    types: types,
                    symbols: symbols,
                    interner: interner,
                    arena: module.arena,
                    into: &newBody
                )
                boxedArguments[argIndex] = boxedResult
            }
        }
        return boxedArguments
    }

    func resolveUnboxForCall(
        callSymbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        receiver: KIRExprID? = nil,
        result: KIRExprID?,
        signatureByName: [InternedString: FunctionSignature],
        module: KIRModule,
        types: TypeSystem?,
        symbols: SymbolTable?,
        boxingCalleeTable: BoxingCalleeTable,
        nullableGenericResults: inout Set<KIRExprID>,
        boxedReturnCallees: Set<InternedString> = []
    ) -> (InternedString, TypeID)? {
        guard !boxedReturnCallees.contains(callee) else { return nil }
        guard let types, let result else { return nil }
        var returnType: TypeID?
        if let callSymbol {
            returnType = returnTypeForCall(callSymbol: callSymbol, symbols: symbols)
        }
        if returnType == nil {
            returnType = signatureByName[callee]?.returnType
        }
        guard let returnType else { return nil }
        let returnKind = resolveValueClassKind(types.kind(of: returnType), types: types, symbols: symbols)
        let resultType = module.arena.exprType(result)
        guard let resultType else { return nil }
        let resultKind = resolveValueClassKind(types.kind(of: resultType), types: types, symbols: symbols)

        if case let .typeParam(returnTypeParam) = types.kind(of: returnType),
           let inferredReturnType = inferFunctionTypeParameter(
               returnTypeParam.symbol,
               callSymbol: callSymbol,
               arguments: arguments,
               receiver: receiver,
               module: module,
               types: types,
               symbols: symbols
           )
        {
            let concreteReturnType: TypeID = switch returnTypeParam.nullability {
            case .nonNull: inferredReturnType
            case .nullable, .platformType: types.makeNullable(inferredReturnType)
            }
            if types.nullability(of: concreteReturnType) == .nullable {
                // Generic return types are erased in the callee signature. Recover
                // nullable specializations from their actual generic arguments so
                // the result keeps its nullable representation across the call.
                module.arena.setExprType(concreteReturnType, for: result)
                nullableGenericResults.insert(result)
                return nil
            }
        }

        guard needsUnboxing(sourceKind: returnKind, targetKind: resultKind, symbols: symbols) else {
            return nil
        }
        guard let unboxCallee = unboxingCallee(
            sourceKind: returnKind,
            targetKind: resultKind,
            boxingCalleeTable: boxingCalleeTable,
            types: types,
            symbols: symbols,
            preferStaticPrimitive: true
        ) else {
            return nil
        }
        return (unboxCallee, returnType)
    }

    private func inferFunctionTypeParameter(
        _ targetSymbol: SymbolID,
        callSymbol: SymbolID?,
        arguments: [KIRExprID],
        receiver: KIRExprID?,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?
    ) -> TypeID? {
        guard let callSymbol,
              let symbols,
              let signature = symbols.functionSignature(for: callSymbol),
              signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount).contains(targetSymbol)
        else {
            return nil
        }

        var actualTypes: [(formal: TypeID, actual: TypeID)] = []
        let receiverArgumentCount = signature.receiverType != nil && arguments.count == signature.parameterTypes.count + 1
            ? 1
            : 0
        if let formalReceiverType = signature.receiverType {
            if receiverArgumentCount == 1,
               let actualReceiverType = module.arena.exprType(arguments[0])
            {
                actualTypes.append((formalReceiverType, actualReceiverType))
            } else if let receiver,
                      let actualReceiverType = module.arena.exprType(receiver)
            {
                actualTypes.append((formalReceiverType, actualReceiverType))
            }
        }
        for (formalType, argument) in zip(signature.parameterTypes, arguments.dropFirst(receiverArgumentCount)) {
            guard let actualType = module.arena.exprType(argument) else { continue }
            actualTypes.append((formalType, actualType))
        }

        var inferred: [SymbolID: TypeID] = [:]
        var conflictingBindings: Set<SymbolID> = []
        let functionTypeParameters = Set(signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount))
        for (formalType, actualType) in actualTypes {
            collectFunctionTypeParameterBindings(
                formal: formalType,
                actual: actualType,
                typeParameters: functionTypeParameters,
                types: types,
                conflictingBindings: &conflictingBindings,
                into: &inferred
            )
        }
        return conflictingBindings.contains(targetSymbol) ? nil : inferred[targetSymbol]
    }

    private func collectFunctionTypeParameterBindings(
        formal: TypeID,
        actual: TypeID,
        typeParameters: Set<SymbolID>,
        types: TypeSystem,
        conflictingBindings: inout Set<SymbolID>,
        into inferred: inout [SymbolID: TypeID]
    ) {
        switch (types.kind(of: formal), types.kind(of: actual)) {
        case let (.typeParam(formalParam), _)
            where typeParameters.contains(formalParam.symbol):
            if let previous = inferred[formalParam.symbol], previous != actual {
                conflictingBindings.insert(formalParam.symbol)
            } else {
                inferred[formalParam.symbol] = actual
            }
        case let (.classType(formalClass), .classType(actualClass))
            where formalClass.classSymbol == actualClass.classSymbol
                && formalClass.args.count == actualClass.args.count:
            for (formalArg, actualArg) in zip(formalClass.args, actualClass.args) {
                guard let formalInner = typeArgumentType(formalArg),
                      let actualInner = typeArgumentType(actualArg)
                else {
                    continue
                }
                collectFunctionTypeParameterBindings(
                    formal: formalInner,
                    actual: actualInner,
                    typeParameters: typeParameters,
                    types: types,
                    conflictingBindings: &conflictingBindings,
                    into: &inferred
                )
            }
        default:
            break
        }
    }

    private func typeArgumentType(_ argument: TypeArg) -> TypeID? {
        switch argument {
        case let .invariant(type), let .out(type), let .in(type): type
        case .star: nil
        }
    }

    func returnTypeForCall(
        callSymbol: SymbolID?,
        symbols: SymbolTable?
    ) -> TypeID? {
        guard let callSymbol, let symbols else {
            return nil
        }
        return symbols.functionSignature(for: callSymbol)?.returnType
    }
}
