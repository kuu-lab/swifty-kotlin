
extension ABILoweringPass {
    func applyArgumentBoxing(
        arguments: [KIRExprID],
        signature: FunctionSignature,
        receiverOffset: Int,
        captureOffset: Int = 0,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        boxingCalleeTable: BoxingCalleeTable,
        callee: InternedString?,
        interner: StringInterner,
        boxTypeParamArguments: Bool = false,
        sema: SemaModule? = nil,
        cache: KIRNominalDispatchCache? = nil,
        newBody: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        var boxedArguments = arguments
        // Erased and nullable slots carry boxes even after a smart cast.
        // Concrete primitive receivers and parameters require the raw payload;
        // an already raw value must retain its bits (including -0.0).
        let receiverIndex = captureOffset + receiverOffset - 1
        // Enum bodies require raw ordinals. Only unwrap an argument when
        // the formal type is the same non-null enum; nullable enum / Any
        // extensions keep their boxes. Default stubs carry their receiver as
        // an ordinary parameter, so use this rule for both kinds of slot.
        func unboxNullableEnum(_ argument: KIRExprID, to targetType: TypeID) -> KIRExprID? {
            guard case let .classType(targetClass) = types.kind(of: targetType),
                  targetClass.nullability == .nonNull,
                  symbols?.symbol(targetClass.classSymbol)?.kind == .enumClass,
                  let argType = intrinsicArgType(argument, arena: module.arena, types: types),
                  case let .classType(argClass) = types.kind(of: argType),
                  argClass.nullability == .nullable,
                  argClass.classSymbol == targetClass.classSymbol,
                  let unboxCallee = unboxingCallee(
                      sourceKind: types.kind(of: argType),
                      targetKind: types.kind(of: targetType),
                      boxingCalleeTable: boxingCalleeTable,
                      types: types,
                      symbols: symbols,
                      preferStaticPrimitive: true
                  )
            else { return nil }
            return emitNonThrowingCall(
                callee: unboxCallee,
                arg: argument,
                resultType: targetType,
                arena: module.arena,
                into: &newBody
            )
        }
        func unboxPrimitive(_ argument: KIRExprID, to targetType: TypeID) -> KIRExprID? {
            guard case .primitive(_, .nonNull) = types.kind(of: targetType),
                  let argType = intrinsicArgType(argument, arena: module.arena, types: types),
                  argType != targetType,
                  let unboxCallee = unboxingCallee(
                      sourceKind: types.kind(of: argType),
                      targetKind: types.kind(of: targetType),
                      boxingCalleeTable: boxingCalleeTable,
                      types: types,
                      symbols: symbols,
                      preferStaticPrimitive: true
                  )
            else { return nil }
            return emitNonThrowingCall(
                callee: unboxCallee, arg: argument, resultType: targetType,
                arena: module.arena, into: &newBody
            )
        }
        // A `V?`/reference slot holds a nominal box while the `V` formal
        // expects the payload: `v?.member()` receivers and value parameters
        // unwrap it here (KUU-3115).
        func unboxNullableUnderlyingValueClass(_ argument: KIRExprID, to targetType: TypeID) -> KIRExprID? {
            guard let symbols,
                  let vcSymbol = nullableUnderlyingValueClassSymbol(
                      of: types.kind(of: targetType), types: types, symbols: symbols
                  ),
                  let argType = intrinsicArgType(argument, arena: module.arena, types: types),
                  valueClassUnboxSourceIsBoxed(types.kind(of: argType), symbols: symbols)
            else { return nil }
            let unboxed = module.arena.appendTemporary(type: targetType)
            emitValueClassUnboxCall(
                value: argument, classSymbol: vcSymbol, result: unboxed,
                resultType: targetType, types: types, symbols: symbols,
                interner: interner, arena: module.arena, into: &newBody
            )
            return unboxed
        }
        if receiverOffset > 0, arguments.indices.contains(receiverIndex),
           let receiverType = signature.receiverType,
           let unboxed = unboxNullableEnum(arguments[receiverIndex], to: receiverType)
        {
            boxedArguments[receiverIndex] = unboxed
        }
        if receiverOffset > 0, arguments.indices.contains(receiverIndex),
           let receiverType = signature.receiverType,
           let unboxed = unboxPrimitive(arguments[receiverIndex], to: receiverType)
        {
            boxedArguments[receiverIndex] = unboxed
        }
        if receiverOffset > 0, arguments.indices.contains(receiverIndex),
           let receiverType = signature.receiverType,
           let unboxed = unboxNullableUnderlyingValueClass(arguments[receiverIndex], to: receiverType)
        {
            boxedArguments[receiverIndex] = unboxed
        }
        // Interface dispatch and abstract Enum properties require a tagged
        // enum box. Generic extension receivers have the same erased ABI as
        // generic value parameters; substituting a raw ordinal here bypasses
        // the enum metadata needed by the extension body. `Any`/`Any?` (and
        // intersection-erased) receivers are the same reference boundary:
        // without the box, `is` checks and entry equality inside the body see
        // a bare ordinal and never match (KUU-3224).
        func enumReceiverNeedsBoxing(_ type: TypeID) -> Bool {
            switch types.kind(of: type) {
            case .typeParam:
                return boxTypeParamArguments
            case .any, .intersection:
                return true
            case let .classType(classType):
                guard let info = symbols?.symbol(classType.classSymbol) else { return false }
                if info.kind == .enumClass {
                    // A nullable enum receiver holds the box-or-sentinel
                    // form, so a raw non-null ordinal must still be boxed.
                    return classType.nullability != .nonNull
                }
                return info.kind == .interface
                    || info.fqName == ["kotlin", "Enum"].map(interner.intern)
            default:
                return false
            }
        }
        // Context parameters are ordinary hidden ABI parameters after any
        // dispatch/extension receiver and before source value parameters.
        // Normalize them separately so they do not shift onto the first
        // source parameter below (for example, Int context + Array argument).
        for (contextIndex, contextType) in signature.contextParameterTypes.enumerated() {
            let argumentIndex = captureOffset + receiverOffset + contextIndex
            guard arguments.indices.contains(argumentIndex),
                  let argumentType = intrinsicArgType(arguments[argumentIndex], arena: module.arena, types: types)
            else {
                continue
            }
            if let unboxed = unboxNullableEnum(arguments[argumentIndex], to: contextType) {
                boxedArguments[argumentIndex] = unboxed
                continue
            }
            if let unboxed = unboxPrimitive(arguments[argumentIndex], to: contextType) {
                boxedArguments[argumentIndex] = unboxed
                continue
            }
            if let unboxed = unboxNullableUnderlyingValueClass(arguments[argumentIndex], to: contextType) {
                boxedArguments[argumentIndex] = unboxed
                continue
            }
            if let boxCallee = boxingCallee(
                argType: argumentType,
                paramType: contextType,
                callee: callee,
                types: types,
                interner: interner,
                boxingCalleeTable: boxingCalleeTable,
                symbols: symbols,
                boxTypeParamBoundary: boxTypeParamArguments,
                preferStaticPrimitive: true
            ) {
                let boxedResult = module.arena.appendTemporary(type: contextType)
                emitBoxCallWithValueClassTag(
                    boxCallee: boxCallee,
                    value: arguments[argumentIndex],
                    rawSourceKind: types.kind(of: argumentType),
                    result: boxedResult,
                    resultType: contextType,
                    types: types,
                    symbols: symbols,
                    interner: interner,
                    arena: module.arena,
                    sema: sema,
                    cache: cache,
                    into: &newBody
                )
                boxedArguments[argumentIndex] = boxedResult
            }
        }
        // A statically called member whose receiver is an interface (an
        // interface default method, or a callable-reference dispatch thunk)
        // dispatches through `this`'s itable, so an enum receiver -- a raw
        // ordinal until something widens it -- must arrive as its box, the
        // same way an enum value argument for an interface parameter does.
        if receiverOffset > 0, arguments.indices.contains(receiverIndex),
           case let receiver = arguments[receiverIndex],
           let receiverType = signature.receiverType,
           let argType = intrinsicArgType(receiver, arena: module.arena, types: types),
           case let .classType(argClass) = types.kind(of: argType),
           argClass.nullability == .nonNull,
           let argInfo = symbols?.symbol(argClass.classSymbol),
           argInfo.kind == .enumClass,
           enumReceiverNeedsBoxing(receiverType)
        {
            boxedArguments[receiverIndex] = boxValueForAnySlot(
                receiver,
                sourceType: argType,
                types: types,
                symbols: symbols,
                interner: interner,
                arena: module.arena,
                resultType: receiverType,
                requireNonNull: true,
                boxingCalleeTable: boxingCalleeTable,
                sema: sema,
                cache: cache,
                into: &newBody.instructions
            )
        }
        // A `.typeParam` extension receiver is erased at the same ABI boundary
        // as a type-parameter value argument: the callee body reads `this` as
        // an Any slot. A primitive receiver must therefore be boxed, or its
        // raw word is reinterpreted as a pointer — e.g. `'c'.myToString()`
        // rendering `99` instead of `c`. Enum receivers keep the dedicated
        // tagged box above (a plain `kk_box_int` would lose the entry name).
        if receiverOffset > 0, arguments.indices.contains(receiverIndex),
           boxedArguments[receiverIndex] == arguments[receiverIndex],
           let receiverType = signature.receiverType,
           case .typeParam = types.kind(of: types.makeNonNullable(receiverType)),
           let argType = intrinsicArgType(arguments[receiverIndex], arena: module.arena, types: types),
           let boxCallee = boxingCallee(
               argType: argType,
               paramType: receiverType,
               callee: callee,
               types: types,
               interner: interner,
               boxingCalleeTable: boxingCalleeTable,
               symbols: symbols,
               boxTypeParamBoundary: boxTypeParamArguments,
               preferStaticPrimitive: true
           )
        {
            let boxedResult = module.arena.appendTemporary(type: receiverType)
            emitBoxCallWithValueClassTag(
                boxCallee: boxCallee,
                value: arguments[receiverIndex],
                rawSourceKind: types.kind(of: argType),
                result: boxedResult,
                resultType: receiverType,
                types: types,
                symbols: symbols,
                interner: interner,
                arena: module.arena,
                sema: sema,
                cache: cache,
                into: &newBody
            )
            boxedArguments[receiverIndex] = boxedResult
        }
        let parameterTypes = signature.parameterTypes
        let varargFlags = signature.valueParameterIsVararg
        for argIndex in arguments.indices {
            let paramIndex = argIndex - captureOffset - receiverOffset - signature.contextParameterTypes.count
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
            if let unboxed = unboxNullableEnum(arguments[argIndex], to: paramType) {
                boxedArguments[argIndex] = unboxed
                continue
            }
            if let unboxed = unboxPrimitive(arguments[argIndex], to: paramType) {
                boxedArguments[argIndex] = unboxed
                continue
            }
            if let unboxed = unboxNullableUnderlyingValueClass(arguments[argIndex], to: paramType) {
                boxedArguments[argIndex] = unboxed
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
                    sema: sema,
                    cache: cache,
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
        captureOffset: Int = 0,
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
               captureOffset: captureOffset,
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

    /// KUU-3115: a call whose declared return type and result-slot type sit on
    /// opposite sides of a nullable-underlying value class's `V`/`V?` boundary
    /// needs `kk_value_class_box`/`kk_value_class_unbox` — the primitive
    /// box/unbox tables cannot express that representation change. Returns the
    /// value-class symbol, whether the result must be *boxed* (vs unboxed),
    /// and the callee's declared return type for the intermediate slot.
    func resolveValueClassResultConversion(
        callSymbol: SymbolID?,
        callee: InternedString,
        result: KIRExprID?,
        signatureByName: [InternedString: FunctionSignature],
        module: KIRModule,
        types: TypeSystem?,
        symbols: SymbolTable?,
        boxedReturnCallees: Set<InternedString> = []
    ) -> (classSymbol: SymbolID, boxing: Bool, returnType: TypeID)? {
        guard !boxedReturnCallees.contains(callee) else { return nil }
        guard let types, let symbols, let result,
              let resultType = module.arena.exprType(result)
        else { return nil }
        var returnType: TypeID?
        if let callSymbol {
            returnType = returnTypeForCall(callSymbol: callSymbol, symbols: symbols)
        }
        if returnType == nil {
            returnType = signatureByName[callee]?.returnType
        }
        guard let returnType else { return nil }
        let rawReturnKind = types.kind(of: returnType)
        let rawResultKind = types.kind(of: resultType)
        if let vcSymbol = nullableUnderlyingValueClassSymbol(
            of: rawResultKind, types: types, symbols: symbols
        ), valueClassUnboxSourceIsBoxed(rawReturnKind, symbols: symbols) {
            return (vcSymbol, false, returnType)
        }
        if let vcSymbol = nullableUnderlyingValueClassSymbol(
            of: rawReturnKind, types: types, symbols: symbols
        ), valueClassBoxTargetIsBoxed(rawResultKind, symbols: symbols) {
            return (vcSymbol, true, returnType)
        }
        return nil
    }

    /// Emits the `kk_value_class_*` conversion
    /// `resolveValueClassResultConversion` selected, rewriting `from`'s value
    /// into `to` (KUU-3115).
    func appendValueClassResultConversion(
        conversion: (classSymbol: SymbolID, boxing: Bool, returnType: TypeID),
        from: KIRExprID,
        to: KIRExprID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner,
        into newBody: inout KIRLoweringEmitContext
    ) {
        if conversion.boxing {
            emitValueClassBoxCall(
                value: from, classSymbol: conversion.classSymbol, result: to,
                resultType: module.arena.exprType(to),
                types: types, symbols: symbols, interner: interner,
                arena: module.arena, into: &newBody
            )
            return
        }
        emitValueClassUnboxCall(
            value: from, classSymbol: conversion.classSymbol, result: to,
            resultType: module.arena.exprType(to),
            types: types, symbols: symbols, interner: interner,
            arena: module.arena, into: &newBody
        )
    }

    private func inferFunctionTypeParameter(
        _ targetSymbol: SymbolID,
        callSymbol: SymbolID?,
        arguments: [KIRExprID],
        receiver: KIRExprID?,
        captureOffset: Int = 0,
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
        let isMemberExtension = symbols.memberExtensionOwnerSymbol(for: callSymbol) != nil
        let receiverArgumentCount = signature.receiverType == nil ? 0 : (
            isMemberExtension ? (receiver == nil ? 2 : 1)
                : (arguments.count == captureOffset + signature.parameterTypes.count + 1 ? 1 : 0)
        )
        if let formalReceiverType = signature.receiverType {
            let receiverIndex = captureOffset + receiverArgumentCount - 1
            if receiverArgumentCount > 0,
               arguments.indices.contains(receiverIndex),
               let actualReceiverType = module.arena.exprType(arguments[receiverIndex])
            {
                actualTypes.append((formalReceiverType, actualReceiverType))
            } else if let receiver,
                      let actualReceiverType = module.arena.exprType(receiver)
            {
                actualTypes.append((formalReceiverType, actualReceiverType))
            }
        }
        for (formalType, argument) in zip(signature.parameterTypes, arguments.dropFirst(captureOffset + receiverArgumentCount)) {
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
        if let returnType = symbols.functionSignature(for: callSymbol)?.returnType {
            return returnType
        }
        // External property bridges are emitted as calls to the property symbol
        // itself, rather than to a getter accessor. Preserve their declared
        // generic result type so ABI lowering can unbox a concrete use site.
        if symbols.symbol(callSymbol)?.kind == .property,
           let linkName = symbols.externalLinkNameIfKnown(for: callSymbol),
           !linkName.isEmpty,
           let returnType = symbols.propertyType(for: callSymbol)
        {
            return returnType
        }
        // An interface property's dynamic getter has a synthetic ID even
        // when its declaration was imported from a library. The declaration
        // still carries the erased T return type needed to unbox Double and
        // other concrete values after dispatch.
        if let accessor = SyntheticSymbolScheme.decodedPropertyAccessor(callSymbol),
           accessor.kind == .getter {
            return symbols.propertyType(for: accessor.property)
        }
        return nil
    }
}
