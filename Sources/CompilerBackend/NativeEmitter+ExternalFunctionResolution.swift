import RuntimeABI
import CompilerCore

extension NativeEmitter.FunctionEmissionContext {

    func declareExternalFunction(
        named calleeName: String,
        argumentCount: Int,
        appendThrownChannel: Bool
    ) -> NativeEmitter.LLVMFunction? {
        // Lambda bodies may reach codegen with callee "length" when receiver type is not
        // available during KIR lowering (e.g. mapIndexed { _, v -> v.length }).
        let effectiveName: String = if NativeEmitter.isStringLengthAggregateAccessorName(calleeName),
                                       argumentCount == 1,
                                       !appendThrownChannel
        {
            "__kk_string_struct_get_length"
        } else {
            calleeName
        }
        if let existing = externalFunctions[effectiveName] {
            return existing
        }
        if let spec = NativeEmitter.runtimeABIFunctionByName[effectiveName] {
            let parameterTypes: [LLVMCAPIBindings.LLVMTypeRef?] = spec.parameters.map { parameter in
                switch parameter.type {
                case .nullableIntptrPointer:
                    return outThrownPointerType
                case .constUInt8Pointer, .nullableConstUInt8Pointer:
                    // Flat bridges consume native pointers; legacy raw calls carry pointer bits as intptr.
                    return NativeEmitter.flatScalarReturnCallSpecs[effectiveName] != nil
                        || NativeEmitter.flatStringReturnCallSpecs[effectiveName] != nil
                        ? typeLowering?.dataPointerType : int64Type
                default:
                    return int64Type
                }
            }
            return declareExternalFunction(
                named: effectiveName,
                parameterTypes: parameterTypes,
                // Function addresses must agree with the flat String call's native pointer return.
                returnType: NativeEmitter.flatStringReturnCallSpecs[effectiveName] != nil
                    ? typeLowering?.dataPointerType : int64Type
            )
        }
        let maxArgsSeenInBody = maxKIRArgumentCountByExternalCallee[effectiveName] ?? 0
        let effectiveArgumentCount = max(argumentCount, maxArgsSeenInBody)
        var callParameterTypes = Array(repeating: int64Type, count: effectiveArgumentCount)
        if appendThrownChannel {
            callParameterTypes.append(outThrownPointerType)
        }
        guard let externalType = bindings.functionType(
            returnType: int64Type,
            parameters: callParameterTypes,
            isVarArg: false
        ) else {
            return nil
        }
        let externalValue = bindings.getNamedFunction(module: llvmModule, name: effectiveName)
            ?? bindings.addFunction(module: llvmModule, name: effectiveName, functionType: externalType)
        guard let externalValue else {
            return nil
        }
        let declared = NativeEmitter.LLVMFunction(value: externalValue, type: externalType)
        externalFunctions[effectiveName] = declared
        return declared
    }

    func declareExternalFunction(
        named calleeName: String,
        parameterTypes: [LLVMCAPIBindings.LLVMTypeRef?],
        returnType: LLVMCAPIBindings.LLVMTypeRef?
    ) -> NativeEmitter.LLVMFunction? {
        let key = "\(calleeName)#typed#\(parameterTypes.count)"
        if let existing = externalFunctions[key] {
            return existing
        }
        guard let externalType = bindings.functionType(
            returnType: returnType,
            parameters: parameterTypes,
            isVarArg: false
        ) else {
            return nil
        }
        let externalValue = bindings.getNamedFunction(module: llvmModule, name: calleeName)
            ?? bindings.addFunction(module: llvmModule, name: calleeName, functionType: externalType)
        guard let externalValue else {
            return nil
        }
        let declared = NativeEmitter.LLVMFunction(value: externalValue, type: externalType)
        externalFunctions[key] = declared
        return declared
    }

    func flattenedRuntimeParameterTypes(
        argumentCount: Int,
        stringArgumentPositions: [Int]
    ) -> [LLVMCAPIBindings.LLVMTypeRef?]? {
        guard let typeLowering else {
            return nil
        }
        let stringPositions = Set(stringArgumentPositions)
        var parameterTypes: [LLVMCAPIBindings.LLVMTypeRef?] = []
        for index in 0..<argumentCount {
            if stringPositions.contains(index) {
                parameterTypes.append(contentsOf: [
                    typeLowering.dataPointerType,
                    int64Type,
                    int64Type,
                    int64Type,
                ])
            } else {
                parameterTypes.append(int64Type)
            }
        }
        return parameterTypes
    }

    func flattenedRuntimeArguments(
        values argumentValues: [LLVMCAPIBindings.LLVMValueRef],
        types argumentTypes: [TypeID?],
        ids argumentIDs: [KIRExprID?],
        argumentCount: Int,
        stringArgumentPositions: [Int],
        suffix: String
    ) -> [LLVMCAPIBindings.LLVMValueRef]? {
        guard argumentValues.count >= argumentCount,
              argumentTypes.count >= argumentCount,
              argumentIDs.count >= argumentCount
        else {
            return nil
        }
        let stringPositions = Set(stringArgumentPositions)
        var flattened: [LLVMCAPIBindings.LLVMValueRef] = []
        for index in 0..<argumentCount {
            if stringPositions.contains(index) {
                let stringValue: LLVMCAPIBindings.LLVMValueRef
                if let argumentID = argumentIDs[index],
                   isZeroConstant(argumentID),
                   let typeLowering,
                   let nullString = buildNullStringAggregate(
                       builder: builder,
                       lowering: typeLowering,
                       name: "string_null_flat_arg\(suffix)_\(index)"
                   )
                {
                    stringValue = nullString
                } else if stringAggregateBridge.isStringAggregateType(argumentTypes[index]) {
                    stringValue = argumentValues[index]
                } else if isCharSequenceRuntimeStringType(argumentTypes[index]),
                          let bridged = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                              argumentValues[index],
                              suffix: "\(suffix)_arg\(index)_charseq"
                          ) {
                    stringValue = bridged
                } else if !isPrimitiveType(argumentTypes[index]),
                          let bridged = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                              argumentValues[index],
                              suffix: "\(suffix)_arg\(index)_raw"
                          ) {
                    // Fallback for boxed string pointers in any/unknown-typed expressions
                    // (e.g. kk_list_iterator_next result used in a string template).
                    // Excluded: primitive types (Int, Bool, Char…) which are never string boxes.
                    stringValue = bridged
                } else {
                    return nil
                }
                guard let fields = stringAggregateBridge.stringAggregateFields(stringValue, suffix: "\(suffix)_arg\(index)") else { return nil }
                flattened.append(contentsOf: fields)
            } else {
                flattened.append(argumentValues[index])
            }
        }
        return flattened
    }

    func resolveUnnamedInternalFunction(
        named calleeName: String,
        argumentCount: Int,
        argumentTypes: [TypeID?],
        appendThrownChannel _: Bool
    ) -> (symbol: SymbolID, function: NativeEmitter.LLVMFunction)? {
        // Match by KIR param count (user args only); outThrown is appended by codegen.
        let lookupKey = NativeEmitter.FunctionLookupKey(name: calleeName, parameterCount: argumentCount)
        let candidates = internalFunctionsByLookupKey[lookupKey, default: []].compactMap { candidate -> (symbol: SymbolID, function: NativeEmitter.LLVMFunction, parameters: [TypeID])? in
            guard let llvmFunction = internalFunctions[candidate.symbol] else {
                return nil
            }
            return (candidate.symbol, llvmFunction, candidate.params.map(\.type))
        }
        let exactMatches = candidates.filter { candidate in
            guard argumentTypes.count == candidate.parameters.count else {
                return false
            }
            return zip(argumentTypes, candidate.parameters).allSatisfy { argumentType, parameterType in
                guard let argumentType else {
                    return false
                }
                return argumentType == parameterType
            }
        }
        if exactMatches.count == 1, let match = exactMatches.first {
            return (match.symbol, match.function)
        }
        if candidates.count == 1, let match = candidates.first {
            return (match.symbol, match.function)
        }
        return nil
    }

    func internalSignature(for symbol: SymbolID?) -> (parameters: [TypeID], returnType: TypeID)? {
        guard let symbol else {
            return nil
        }
        return internalSignatures[symbol]
    }

    func sourceReceiverTypes(for symbol: SymbolID, signature: FunctionSignature) -> [TypeID] {
        var receivers = [signature.receiverType].compactMap { $0 }
        if let symbols, let typeSystem,
           let owner = symbols.memberExtensionOwnerSymbol(for: symbol)
        {
            let ownerArgs: [TypeArg] = signature.typeParameterSymbols
                .prefix(signature.classTypeParameterCount)
                .map { .invariant(typeSystem.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull)))) }
            let ownerType = typeSystem.make(.classType(ClassType(
                classSymbol: owner, args: ownerArgs, nullability: .nonNull
            )))
            receivers.insert(ownerType, at: 0)
        }
        return receivers
    }

    func sourceExternalSignature(
        for symbol: SymbolID?,
        argumentCount: Int
    ) -> (parameters: [TypeID], returnType: TypeID)? {
        guard let symbol,
              let symbols,
              let typeSystem,
              let signature = symbols.functionSignature(for: symbol),
              let externalLinkName = symbols.externalLinkName(for: symbol),
              !externalLinkName.isEmpty
        else {
            return nil
        }
        let omitsRuntimeReceiver = NativeEmitter.runtimeABIFunctionByName[externalLinkName] != nil
            && argumentCount == signature.contextParameterTypes.count + signature.parameterTypes.count
        let receivers = omitsRuntimeReceiver ? [] : sourceReceiverTypes(for: symbol, signature: signature)
        let parameters = receivers + signature.contextParameterTypes + signature.parameterTypes
        guard parameters.count == argumentCount else {
            return nil
        }

        func isHandleLike(_ type: RuntimeABICType) -> Bool {
            switch type {
            case .intptr, .opaquePointer, .nullableOpaquePointer:
                return true
            default:
                return false
            }
        }

        let resolvedParameters: [TypeID]
        let resolvedReturnType: TypeID
        func isVarargParameter(_ parameterIndex: Int) -> Bool {
            let valueParameterIndex = parameterIndex - receivers.count - signature.contextParameterTypes.count
            return signature.valueParameterIsVararg.indices.contains(valueParameterIndex)
                && signature.valueParameterIsVararg[valueParameterIndex]
        }
        let isRawNumericComparisonHelper = [
            "kk_min_float", "kk_max_float", "kk_min_double", "kk_max_double",
        ].contains(externalLinkName)
        if let spec = NativeEmitter.runtimeABIFunctionByName[externalLinkName] {
            // Runtime callees that throw carry a trailing `outThrown` channel
            // that is not part of the Kotlin parameter list, so exclude it
            // when matching against the source-level signature.
            let abiValueParameters = spec.parameters.filter { parameter in
                !(parameter.name == "outThrown" && parameter.type == .nullableIntptrPointer)
            }
            if abiValueParameters.count == parameters.count {
                resolvedParameters = zip(parameters, abiValueParameters).enumerated().map { index, pair in
                    let (kotlinType, abiParam) = pair
                    if isVarargParameter(index) {
                        // A vararg parameter is passed as one erased array/list
                        // handle at the compiler ABI boundary, even though the
                        // metadata type records its element type.
                        return typeSystem.anyType
                    }
                    if isRawNumericComparisonHelper, abiParam.type == .intptr {
                        // These helpers consume IEEE bit patterns even though their
                        // bundled Kotlin declarations are Float/Double-typed.
                        return typeSystem.intType
                    }
                    if stringAggregateBridge.isStringAggregateType(kotlinType), isHandleLike(abiParam.type) {
                        return typeSystem.intType
                    }
                    return kotlinType
                }
            } else {
                resolvedParameters = parameters.enumerated().map { index, parameter in
                    isVarargParameter(index) ? typeSystem.anyType : parameter
                }
            }
            if isRawNumericComparisonHelper, spec.returnType == .intptr {
                // Keep the raw-bit return type aligned with RuntimeABI when an
                // inline precompiled body retains the helper's source symbol.
                resolvedReturnType = typeSystem.intType
            } else if stringAggregateBridge.isStringAggregateType(signature.returnType), isHandleLike(spec.returnType) {
                resolvedReturnType = typeSystem.intType
            } else {
                resolvedReturnType = symbols.functionABIReturnType(for: symbol) ?? signature.returnType
            }
        } else {
            resolvedParameters = parameters.enumerated().map { index, parameter in
                isVarargParameter(index) ? typeSystem.anyType : parameter
            }
            resolvedReturnType = symbols.functionABIReturnType(for: symbol) ?? signature.returnType
        }
        return (resolvedParameters, resolvedReturnType)
    }

}
