import CompilerCore

/// Declaring nominal (class/object/enum/annotation/interface) of a vtable
/// member symbol, used to recover the slot's layout owner at virtual-call
/// sites.
private func virtualCallNominalOwner(for member: SymbolID, symbols: SymbolTable) -> SymbolID? {
    let property = symbols.propertySymbol(forAccessor: member)
        ?? symbols.accessorOwnerProperty(for: member)
    var current = symbols.parentSymbol(for: property ?? member)
    var visited: Set<SymbolID> = []
    while let currentSymbol = current, visited.insert(currentSymbol).inserted {
        guard let info = symbols.symbol(currentSymbol) else {
            return nil
        }
        switch info.kind {
        case .class, .object, .enumClass, .annotationClass, .interface:
            return currentSymbol
        default:
            current = symbols.parentSymbol(for: currentSymbol)
        }
    }
    return nil
}

extension NativeEmitter.FunctionEmissionContext {

    func emitVirtualCall(
        symbol: SymbolID?,
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        usesThrownChannel: Bool,
        thrownResult: KIRExprID?,
        dispatch: KIRDispatchKind,
        instructionIndex: Int
    ) {
        guard !bindings.hasTerminator(currentBlock) else {
            return
        }

        let calleeName = interner.resolve(callee)
        let argumentValues = [resolveValue(receiver)] + arguments.map(resolveValue)
        let argumentTypes = [module.arena.exprType(receiver)] + arguments.map(module.arena.exprType)
        // A vtable slot retains the erased signature of its root-most
        // declaration. The call-site symbol may be a specialized override
        // whose native String ABI differs from the bridge registered in that
        // slot, so recover the slot contract before choosing an indirect-call
        // type.
        let vtableABISymbol: SymbolID? = {
            guard case let .vtable(slot) = dispatch,
                  let symbol,
                  symbol != .invalid,
                  let symbols
            else {
                return nil
            }

            guard let owner = virtualCallNominalOwner(for: symbol, symbols: symbols),
                  let layout = symbols.nominalLayout(for: owner)
            else {
                return nil
            }

            var distances: [SymbolID: Int] = [owner: 0]
            var pending = [owner]
            var head = 0
            while head < pending.count {
                let current = pending[head]
                head += 1
                let distance = (distances[current] ?? 0) + 1
                for supertype in symbols.directSupertypes(for: current) {
                    guard distances[supertype] == nil,
                          let info = symbols.symbol(supertype)
                    else {
                        continue
                    }
                    switch info.kind {
                    case .class, .object, .enumClass, .annotationClass, .interface:
                        distances[supertype] = distance
                        pending.append(supertype)
                        if info.flags.contains(.expectDeclaration),
                           let actual = symbols.actualSymbol(for: supertype),
                           symbols.symbol(actual)?.kind == info.kind,
                           distances[actual] == nil
                        {
                            distances[actual] = distance
                            pending.append(actual)
                        }
                    default:
                        continue
                    }
                }
            }

            let candidates = layout.vtableSlots.compactMap { candidate, candidateSlot -> (distance: Int, symbol: SymbolID)? in
                guard candidateSlot == slot else {
                    return nil
                }
                let candidateProperty = symbols.propertySymbol(forAccessor: candidate)
                    ?? symbols.accessorOwnerProperty(for: candidate)
                    ?? (symbols.symbol(candidate)?.kind == .property ? candidate : nil)
                // A runtime-builtin root such as `kotlin.Any.toString` has
                // no emitted Kotlin ABI to recover, so anchoring on it would
                // type a flat-String override slot as a raw Int handle.
                let candidateHasEmittedABI = internalFunctions[candidate] != nil
                    || symbols.externalLinkName(for: candidate)?.hasPrefix("kk_fn_") == true
                guard candidateProperty != nil
                    || (symbols.functionSignature(for: candidate) != nil && candidateHasEmittedABI),
                      let candidateOwner = virtualCallNominalOwner(for: candidate, symbols: symbols),
                      let distance = distances[candidateOwner]
                else {
                    return nil
                }
                return (distance, candidate)
            }
            return candidates.max { lhs, rhs in
                lhs.distance == rhs.distance
                    ? lhs.symbol.rawValue < rhs.symbol.rawValue
                    : lhs.distance < rhs.distance
            }?.symbol ?? symbol
        }()
        // Use the declared signature, not the substituted call-site
        // type: generic members returning T keep the raw handle ABI
        // even when invoked as String. Getters may require recovering
        // the property's type from the synthetic accessor symbol.
        let virtualCallDeclaredAggregateResult: Bool? = {
            guard typeLowering != nil else {
                return nil
            }
            if calleeName == "get",
               argumentValues.count == 1,
               let signatureSymbol = vtableABISymbol ?? symbol,
               let property = symbols?.propertySymbol(forAccessor: signatureSymbol)
                   ?? symbols?.accessorOwnerProperty(for: signatureSymbol)
            {
                return stringAggregateBridge.isStringAggregateType(symbols?.propertyType(for: property))
            }
            if let signature = (vtableABISymbol ?? symbol).flatMap({ symbols?.functionSignature(for: $0) }) {
                return stringAggregateBridge.isStringAggregateType(signature.returnType)
            }
            return nil
        }()
        // The `Throwable.message` vtable slot uses the raw String?
        // handle ABI: runtime-allocated exceptions answer it with a
        // runtime bridge, and Kotlin getters are registered through a
        // raw-return bridge (`appendObjectVtablePropertyAccessorRegistrations`).
        let isThrowableMessageVirtualGetter: Bool = {
            guard case let .vtable(slot) = dispatch,
                  calleeName == "get",
                  argumentValues.count == 1,
                  let symbols
            else {
                return false
            }
            if let typeSystem,
               let receiverType = module.arena.exprType(receiver),
               case let .classType(receiverClass) = typeSystem.kind(of: receiverType),
               symbols.throwableMessageGetterSlot(
                   for: receiverClass.classSymbol, interner: interner
               ) == slot
            {
                return true
            }
            // Imported inline bodies retain the accessor symbol even
            // when a catch variable's temporary has no receiver type.
            // Recover this particular slot from its declaration rather
            // than treating an unrelated String getter as raw-return.
            guard let symbol,
                  let property = symbols.propertySymbol(forAccessor: symbol)
                      ?? symbols.accessorOwnerProperty(for: symbol),
                  symbols.symbol(property)?.name == interner.intern("message"),
                  let owner = symbols.parentSymbol(for: property)
            else {
                return false
            }
            return symbols.throwableMessageGetterSlot(for: owner, interner: interner) == slot
        }()
        // The Any.toString slot can hold either the raw runtime fallback or a
        // flat-String Kotlin override. Use the raw ABI only when the slot's
        // resolved implementation has no emitted Kotlin ABI; KUU-3197 moved
        // Kotlin overrides back into the slot as flat-ABI functions.
        let isAnyToStringRawABISlot: Bool = {
            guard case let .vtable(slot) = dispatch,
                  let symbols
            else {
                return false
            }
            func slotHasAnyToString(in nominal: SymbolID) -> Bool {
                guard let layout = symbols.nominalLayout(for: nominal) else {
                    return false
                }
                return layout.vtableSlots.contains { candidate, candidateSlot in
                    candidateSlot == slot
                        && symbols.symbol(candidate).map {
                            isSyntheticAnyToStringSymbol($0, interner: interner)
                        } == true
                }
            }
            let receiverNominal: SymbolID? = {
                if let typeSystem,
                   let receiverType = module.arena.exprType(receiver),
                   case let .classType(receiverClass) = typeSystem.kind(of: receiverType)
                {
                    return receiverClass.classSymbol
                }
                guard let symbol,
                      symbol != .invalid,
                      let owner = virtualCallNominalOwner(for: symbol, symbols: symbols)
                else {
                    return nil
                }
                return owner
            }()
            guard let receiverNominal,
                  slotHasAnyToString(in: receiverNominal),
                  let layout = symbols.nominalLayout(for: receiverNominal)
            else {
                return false
            }

            // Data-class synthesis creates its own toString declaration, but
            // that method does not replace the inherited Any slot. In that
            // case the slot still contains the raw runtime fallback even
            // though the call-site symbol names an emitted Kotlin function.
            // Only use the flat ABI when this exact slot has a source-backed
            // Kotlin override registered in the receiver's layout.
            let hasSourceOverrideInSlot = layout.vtableSlots.contains { candidate, candidateSlot in
                guard candidateSlot == slot,
                      let candidateInfo = symbols.symbol(candidate),
                      !isSyntheticAnyToStringSymbol(candidateInfo, interner: interner)
                else {
                    return false
                }
                return internalFunctions[candidate] != nil
                    || symbols.externalLinkName(for: candidate)?.hasPrefix("kk_fn_") == true
            }
            return !hasSourceOverrideInSlot
        }()
        // A vtable slot whose root-most declaration returns a String
        // aggregate (`toString`, `message` getters, `componentN`, ...) is
        // invoked through the flat aggregate convention on every call path:
        // registered implementations are either Kotlin functions with the
        // source ABI or `itableBridgeSymbolForMethod` bridges that adapt to
        // it. Declaring the indirect call as `i64`-returning miscalls the
        // flat implementation — the hidden sret pointer makes the callee
        // treat the receiver argument as its output buffer — so the
        // declared slot signature decides the return type for every member
        // name, not only `get` (KUU-3230).
        let virtualCallReturnsAggregate = !isThrowableMessageVirtualGetter
            && typeLowering != nil
            && (virtualCallDeclaredAggregateResult
                ?? (calleeName == "get"
                    && argumentValues.count == 1
                    && stringAggregateBridge.isStringAggregateType(result.flatMap { module.arena.exprType($0) })))
        let isThrowableToStringVirtualCall: Bool = {
            guard case .vtable = dispatch,
                  let symbols
            else {
                return false
            }
            let isToString = calleeName == "toString"
                || symbol.flatMap { symbols.symbol($0) }
                    .map { interner.resolve($0.name) == "toString" } == true
            guard isToString else {
                return false
            }
            if let symbol,
               NativeEmitter.isThrowableToStringSymbol(symbol, interner: interner, symbols: symbols)
            {
                return true
            }
            guard let typeSystem else {
                return false
            }
            return NativeEmitter.isThrowableType(
                module.arena.exprType(receiver),
                typeSystem: typeSystem,
                interner: interner,
                symbols: symbols
            )
        }()
        let externalCalleeName = NativeEmitter.runtimePrimitiveAlias(
            for: calleeName,
            argumentCount: argumentValues.count,
            resolvedSymbol: symbol
        ) ?? calleeName

        let normalizedSymbol: SymbolID? = if let symbol, symbol != .invalid {
            symbol
        } else {
            SymbolID?.none
        }
        let fallbackInternal: (symbol: SymbolID, function: NativeEmitter.LLVMFunction)? = if normalizedSymbol == nil {
            resolveUnnamedInternalFunction(
                named: calleeName,
                argumentCount: argumentValues.count,
                argumentTypes: argumentTypes,
                appendThrownChannel: usesThrownChannel
            )
        } else {
            nil
        }
        let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
        let effectiveABISymbol = vtableABISymbol ?? effectiveSymbol
        let isInternalCall = effectiveABISymbol.flatMap { internalFunctions[$0] } != nil
        let effectiveExternalName = effectiveABISymbol.flatMap { symbols?.externalLinkName(for: $0) } ?? externalCalleeName
        let sourceExternalCallSignature = !isInternalCall
            ? sourceExternalSignature(
                for: effectiveABISymbol,
                argumentCount: argumentValues.count
            )
            : nil
        let virtualSourceCallSignature: (parameters: [TypeID], returnType: TypeID)? = {
            guard !isInternalCall,
                  let effectiveABISymbol,
                  let symbols,
                  let typeSystem,
                  let signature = symbols.functionSignature(for: effectiveABISymbol),
                  let linkName = symbols.externalLinkName(for: effectiveABISymbol),
                  linkName.hasPrefix("kk_fn_"),
                  (
                      stringAggregateBridge.isStringAggregateType(signature.returnType)
                          || [signature.receiverType].compactMap { $0 }.contains(where: stringAggregateBridge.isStringAggregateType)
                          || signature.parameterTypes.contains(where: stringAggregateBridge.isStringAggregateType)
                  )
            else {
                return nil
            }
            let receivers = sourceReceiverTypes(for: effectiveABISymbol, signature: signature)
            let valueParameters = signature.parameterTypes.enumerated().map { index, parameter in
                // Metadata records a vararg's element type, but its ABI
                // passes one erased array handle, including for String.
                signature.valueParameterIsVararg.indices.contains(index)
                    && signature.valueParameterIsVararg[index]
                    ? typeSystem.anyType : parameter
            }
            let parameters = receivers + valueParameters
            guard parameters.count == argumentValues.count else {
                return nil
            }
            return (parameters: parameters, returnType: signature.returnType)
        }()
        // An interface declaration imported from a library is not in the
        // consumer's internal function table, but its itable entries point
        // at generated Kotlin functions, which always carry the hidden
        // thrown channel. Keep the indirect function type consistent with
        // that source-backed ABI (KSP-712).
        let shouldAppendThrownChannel = usesThrownChannel
            || isThrowableMessageVirtualGetter
            || isAnyToStringRawABISlot
            || isInternalCall
            || sourceExternalCallSignature != nil
            || virtualSourceCallSignature != nil
        let sourceExternalFunction: NativeEmitter.LLVMFunction? = if let sourceCallSignature =
            virtualSourceCallSignature ?? sourceExternalCallSignature
        {
            {
                var parameterTypes = loweredLLVMTypes(for: sourceCallSignature.parameters)
                if shouldAppendThrownChannel {
                    parameterTypes.append(outThrownPointerType)
                }
                return declareExternalFunction(
                    named: effectiveExternalName,
                    parameterTypes: parameterTypes,
                    returnType: loweredLLVMType(
                        for: sourceCallSignature.returnType,
                        lowering: typeLowering,
                        defaultType: int64Type
                    )
                )
            }()
        } else {
            nil
        }

        // Itable slots carry the interface member's signature: a
        // String-returning member is invoked through the flat aggregate
        // convention on every call path (real implementations register
        // flat getters, bridged by itableBridgeSymbolForMethod when the
        // impl ABI differs). The unnamed `__v` fallback must therefore
        // declare the aggregate return for itable String results rather
        // than the raw Int handle used by runtime-registered members,
        // which keeps the indirect-call ABI independent of whether the
        // getter's KIRFunction happens to be emitted in this module.
        //
        // The call-site result type only decides this when the
        // accessor's declared type is unavailable: a generic
        // `val value: T` erases to the raw pointer ABI even when this
        // call site reads it as `Lazy<String>.value`, so a resolved
        // non-aggregate declaration must suppress the flat path.
        let virtualItableFlatAggregateResult = if let result,
                                                  virtualCallDeclaredAggregateResult != false,
                                                  typeLowering != nil
        {
            switch dispatch {
            case .itable, .itableDynamic:
                isStringAggregateExpr(result)
            default:
                false
            }
        } else {
            false
        }

        // For source-backed overrides of String-returning root slots, the
        // slot signature fixes the indirect-call ABI even if the root member
        // links to a raw runtime helper. Runtime fallback entries are handled
        // above; treating those as flat would miscall Kotlin overrides
        // (KUU-3230).
        let sourceExternalFunctionConflictsWithDeclaredABI = virtualCallReturnsAggregate
            && (virtualSourceCallSignature ?? sourceExternalCallSignature)
                .map { !stringAggregateBridge.isStringAggregateType($0.returnType) }
                ?? false

        let calleeFunction: NativeEmitter.LLVMFunction? = if isThrowableMessageVirtualGetter {
            // Only carries the indirect-call type `(Int, Int*) -> Int`.
            declareExternalFunction(
                named: "__kk_throwable_message__vslot",
                argumentCount: 1,
                appendThrownChannel: true
            )
        } else if isAnyToStringRawABISlot {
            // The runtime fallback entry uses `(Int, Int*) -> Int`; Kotlin
            // overrides are selected above with their flat source ABI.
            declareExternalFunction(
                named: "__kk_any_toString__vslot",
                argumentCount: argumentValues.count,
                appendThrownChannel: true
            )
        } else if let effectiveABISymbol,
                  let internalFunction = internalFunctions[effectiveABISymbol]
        {
            internalFunction
        } else if let fallbackInternal {
            fallbackInternal.function
        } else if calleeName.isEmpty {
            nil
        } else if NativeEmitter.isStringLengthAggregateAccessorName(calleeName), argumentValues.count == 1 {
            declareExternalFunction(
                named: "__kk_string_struct_get_length",
                argumentCount: 1,
                appendThrownChannel: false
            )
        } else if isThrowableToStringVirtualCall {
            declareExternalFunction(
                named: "__kk_throwable_toString",
                argumentCount: argumentValues.count,
                appendThrownChannel: true
            )
        } else if let sourceExternalFunction,
                  !sourceExternalFunctionConflictsWithDeclaredABI
        {
            sourceExternalFunction
        } else {
            // Virtual calls go through `fptr`, so this declaration only carries
            // the indirect-call type. Fold arity into the name: a property getter
            // and an unrelated same-named method (e.g. "get") can share
            // `externalCalleeName` in one body, and the plain-name cache would
            // size both to the larger arity. The `_s` suffix marks a
            // source-ABI aggregate return (see `virtualCallReturnsAggregate`)
            // so it cannot alias the raw `Int`-returning shape.
            declareExternalFunction(
                named: "\(externalCalleeName)__v\(argumentValues.count)\(virtualCallReturnsAggregate || virtualItableFlatAggregateResult ? "_s" : "")",
                parameterTypes: Array<LLVMCAPIBindings.LLVMTypeRef?>(
                    repeating: int64Type, count: argumentValues.count
                ) + (shouldAppendThrownChannel ? [outThrownPointerType] : []),
                returnType: virtualCallReturnsAggregate || virtualItableFlatAggregateResult
                    ? loweredLLVMType(
                        for: result.flatMap { module.arena.exprType($0) },
                        lowering: typeLowering,
                        defaultType: int64Type
                    )
                    : int64Type
            )
        }

        guard let calleeFunction else {
            storeResult(result, nil)
            return
        }

        let calleeKIRFunction = effectiveABISymbol.flatMap { module.arena.function(for: $0) }
        let isRuntimeCallbackRawABIVirtualCall = isInternalCall
            && effectiveSymbol.map { runtimeCallbackRawReturnSymbols.contains($0) } == true
        // The unnamed `__v` declaration always takes `i64` parameters even
        // when its return is a flat aggregate, so String-aggregate arguments
        // still need the raw-handle bridging on that fallback path —
        // `virtualCallReturnsAggregate` only describes the return type and
        // must not suppress argument bridging (KUU-3230).
        let shouldBridgeVirtualExternalStringABI = !isInternalCall
            && typeLowering != nil
            && (virtualSourceCallSignature == nil || isThrowableToStringVirtualCall)
            && !virtualItableFlatAggregateResult
        var virtualCallArguments = argumentValues
        if isRuntimeCallbackRawABIVirtualCall {
            virtualCallArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                let (argumentValue, argumentType) = pair
                guard stringAggregateBridge.isStringAggregateType(argumentType) else {
                    return argumentValue
                }
                return stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                    argumentValue,
                    suffix: "\(instructionIndex)_virtual_callback_arg\(index)"
                ) ?? argumentValue
            }
        } else if shouldBridgeVirtualExternalStringABI {
            virtualCallArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                let (argumentValue, argumentType) = pair
                guard stringAggregateBridge.isStringAggregateType(argumentType) else {
                    return argumentValue
                }
                return stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                    argumentValue,
                    suffix: "\(instructionIndex)_virtual_arg\(index)"
                ) ?? argumentValue
            }
        } else if isInternalCall,
                  let calleeKIRFunction
        {
            // Interface dispatch through a KIR-declared function may see a
            // String aggregate at the call site while the erased interface
            // parameter is a raw pointer (or vice-versa). Convert across the
            // boundary so the looked-up function pointer receives/returns the
            // ABI expected by its KIR signature.
            virtualCallArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                let (argumentValue, argumentType) = pair
                let paramType = index < calleeKIRFunction.params.count
                    ? calleeKIRFunction.params[index].type
                    : nil
                return coerceStringValueForType(
                    argumentValue,
                    from: argumentType,
                    to: paramType,
                    suffix: "\(instructionIndex)_virtual_internal_arg\(index)"
                )
            }
        } else if let sourceCallSignature = virtualSourceCallSignature ?? sourceExternalCallSignature {
            // Imported interface members use their declared source ABI.
            // In particular, a null argument must become a String?
            // aggregate before calling a generated Kotlin method.
            virtualCallArguments = zip(argumentValues, sourceCallSignature.parameters).enumerated().map { index, pair in
                let (argumentValue, parameterType) = pair
                let argumentType = argumentTypes.indices.contains(index) ? argumentTypes[index] : nil
                return coerceStringValueForType(
                    argumentValue,
                    from: argumentType,
                    to: parameterType,
                    suffix: "\(instructionIndex)_virtual_source_arg\(index)"
                )
            }
        }

        let lookupFunction: NativeEmitter.LLVMFunction?
        var lookupArgs: [LLVMCAPIBindings.LLVMValueRef] = []
        // The receiver used for the lookup must have the same runtime
        // representation as the indirect getter call. A bundled
        // CharSequence extension may still carry a flat String
        // aggregate at this point; `virtualCallArguments` performs the
        // required boxing before the getter is invoked, while using the
        // original aggregate here makes the runtime look up a bogus
        // object address and report a missing itable entry.
        let lookupReceiver = virtualCallArguments.first ?? resolveValue(receiver)
        switch dispatch {
        case let .vtable(slot):
            lookupFunction = declareExternalFunction(named: "kk_vtable_lookup", argumentCount: 2, appendThrownChannel: false)
            lookupArgs = [
                lookupReceiver,
                bindings.constInt(int64Type, value: UInt64(slot)) ?? bindings.constInt(int64Type, value: 0)!,
            ]
        case let .itable(interfaceSlot, methodSlot):
            lookupFunction = declareExternalFunction(named: "kk_itable_lookup", argumentCount: 3, appendThrownChannel: false)
            lookupArgs = [
                lookupReceiver,
                bindings.constInt(int64Type, value: UInt64(interfaceSlot)) ?? bindings.constInt(int64Type, value: 0)!,
                bindings.constInt(int64Type, value: UInt64(methodSlot)) ?? bindings.constInt(int64Type, value: 0)!,
            ]
        case let .itableDynamic(interfaceTypeID, methodSlot):
            lookupFunction = declareExternalFunction(named: "kk_itable_lookup_dynamic", argumentCount: 3, appendThrownChannel: false)
            lookupArgs = [
                lookupReceiver,
                bindings.constInt(int64Type, value: UInt64(bitPattern: interfaceTypeID)) ?? bindings.constInt(int64Type, value: 0)!,
                bindings.constInt(int64Type, value: UInt64(methodSlot)) ?? bindings.constInt(int64Type, value: 0)!,
            ]
        }

        guard let lookupFn = lookupFunction else { return }
        guard var fptrRaw = bindings.buildCall(
            builder,
            functionType: lookupFn.type,
            callee: lookupFn.value,
            arguments: lookupArgs,
            name: "lookup_raw_\(instructionIndex)"
        ) else { return }

        // Runtime list boxes have no generated List itable. Only the
        // concrete Kotlin search defaults may fill that missing slot;
        // a source implementation's override still wins when present.
        if let effectiveSymbol,
           let symbols,
           let member = symbols.symbol(effectiveSymbol),
           ["indexOf", "lastIndexOf"].contains(interner.resolve(member.name)),
           let owner = symbols.parentSymbol(for: effectiveSymbol),
           symbols.symbol(owner)?.fqName.map(interner.resolve) == ["kotlin", "collections", "List"],
           !member.flags.contains(.abstractType),
           symbols.isSourceBackedSymbol(effectiveSymbol),
           let defaultPointer = bindings.buildPtrToInt(
               builder, value: calleeFunction.value, type: int64Type,
               name: "list_search_default_\(instructionIndex)"
           ),
           let hasOverride = bindings.buildICmpNotEqual(
               builder, lhs: fptrRaw, rhs: zeroValue,
               name: "list_search_override_\(instructionIndex)"
           ),
           let searchPointer = bindings.buildSelect(
               builder, condition: hasOverride, thenValue: fptrRaw, elseValue: defaultPointer,
               name: "list_search_dispatch_\(instructionIndex)"
           )
        {
            fptrRaw = searchPointer
        }

        // Native dispatcher tags have no Kotlin itable. Use the exact
        // source default selected by this compilation's symbol/layout;
        // Kotlin objects must retain their dynamically resolved override.
        if let effectiveSymbol,
           let symbols,
           let member = symbols.symbol(effectiveSymbol),
           ["get", "minusKey"].contains(interner.resolve(member.name)),
           let owner = symbols.parentSymbol(for: effectiveSymbol),
           symbols.symbol(owner)?.fqName.map(interner.resolve) == ["kotlin", "coroutines", "ContinuationInterceptor"],
           !member.flags.contains(.abstractType),
           symbols.isSourceBackedSymbol(effectiveSymbol),
           let defaultPointer = bindings.buildPtrToInt(
               builder, value: calleeFunction.value, type: int64Type,
               name: "dispatcher_default_\(instructionIndex)"
           ),
           let selectMethod = declareExternalFunction(
               named: "__kk_dispatcher_default_method", argumentCount: 3, appendThrownChannel: false
           ),
           let method = bindings.buildCall(
               builder, functionType: selectMethod.type, callee: selectMethod.value,
               arguments: [lookupReceiver, fptrRaw, defaultPointer],
               name: "dispatcher_dispatch_\(instructionIndex)"
           )
        {
            fptrRaw = method
        }

        // RuntimeMapBox and RuntimeSetBox values have no mutable
        // collection itable. Preserve overrides on Kotlin collection
        // implementations, but use the source-backed default when a
        // native collection box has no entry.
        if let effectiveSymbol,
           let symbols,
           let member = symbols.symbol(effectiveSymbol),
           let owner = symbols.parentSymbol(for: effectiveSymbol),
           let ownerName = symbols.symbol(owner)?.fqName.map(interner.resolve),
           !member.flags.contains(.abstractType),
           symbols.isSourceBackedSymbol(effectiveSymbol),
           (ownerName == ["kotlin", "collections", "MutableMap"] && interner.resolve(member.name) == "asJsMapView"
            || ownerName == ["kotlin", "collections", "MutableSet"] && interner.resolve(member.name) == "asJsSetView")
        {
            let defaultFunction: NativeEmitter.LLVMFunction? = if let internalFunction = internalFunctions[effectiveSymbol] {
                internalFunction
            } else if effectiveExternalName.hasPrefix("kk_fn_") {
                declareExternalFunction(
                    named: effectiveExternalName,
                    argumentCount: argumentValues.count,
                    appendThrownChannel: shouldAppendThrownChannel
                )
            } else {
                nil
            }
            if let defaultFunction,
               let defaultPointer = bindings.buildPtrToInt(
                   builder, value: defaultFunction.value, type: int64Type,
                   name: "collection_view_default_\(instructionIndex)"
               ),
               let hasOverride = bindings.buildICmpNotEqual(
                   builder, lhs: fptrRaw, rhs: zeroValue,
                   name: "collection_view_override_\(instructionIndex)"
               ),
               let collectionViewPointer = bindings.buildSelect(
                   builder, condition: hasOverride, thenValue: fptrRaw, elseValue: defaultPointer,
                   name: "collection_view_dispatch_\(instructionIndex)"
               )
            {
                fptrRaw = collectionViewPointer
            }
        }

        // Runtime list boxes have no generated List itable. Preserve
        // overrides on Kotlin list implementations, but use the
        // source-backed default when a native list box has no entry.
        if let effectiveSymbol,
           let symbols,
           let member = symbols.symbol(effectiveSymbol),
           interner.resolve(member.name) == "asJsReadonlyArrayView",
           let owner = symbols.parentSymbol(for: effectiveSymbol),
           symbols.symbol(owner)?.fqName.map(interner.resolve) == ["kotlin", "collections", "List"],
           !member.flags.contains(.abstractType),
           symbols.isSourceBackedSymbol(effectiveSymbol)
        {
            let defaultFunction: NativeEmitter.LLVMFunction? = if let internalFunction = internalFunctions[effectiveSymbol] {
                internalFunction
            } else if effectiveExternalName.hasPrefix("kk_fn_") {
                declareExternalFunction(
                    named: effectiveExternalName,
                    argumentCount: argumentValues.count,
                    appendThrownChannel: shouldAppendThrownChannel
                )
            } else {
                nil
            }
            if let defaultFunction,
               let defaultPointer = bindings.buildPtrToInt(
                   builder, value: defaultFunction.value, type: int64Type,
                   name: "list_view_default_\(instructionIndex)"
               ),
               let hasOverride = bindings.buildICmpNotEqual(
                   builder, lhs: fptrRaw, rhs: zeroValue,
                   name: "list_view_override_\(instructionIndex)"
               ),
               let arrayViewPointer = bindings.buildSelect(
                   builder, condition: hasOverride, thenValue: fptrRaw, elseValue: defaultPointer,
                   name: "list_view_dispatch_\(instructionIndex)"
               )
            {
                fptrRaw = arrayViewPointer
            }
        }

        // Guard against null vtable/itable lookup: if fptrRaw == 0
        // call kk_dispatch_error runtime trap instead of falling back
        // to direct dispatch (GEN-002).
        guard let isNonNull = bindings.buildICmpNotEqual(
            builder,
            lhs: fptrRaw,
            rhs: zeroValue,
            name: "lookup_nonnull_\(instructionIndex)"
        ),
            let useVirtualBlock = bindings.appendBasicBlock(
                context: context,
                function: llvmFunction.value,
                name: "lookup_ok_\(instructionIndex)"
            ),
            let fallbackBlock = bindings.appendBasicBlock(
                context: context,
                function: llvmFunction.value,
                name: "lookup_fallback_\(instructionIndex)"
            ),
            let mergeBlock = bindings.appendBasicBlock(
                context: context,
                function: llvmFunction.value,
                name: "vcall_merge_\(instructionIndex)"
            )
        else {
            return
        }

        _ = bindings.buildCondBr(
            builder,
            condition: isNonNull,
            thenBlock: useVirtualBlock,
            elseBlock: fallbackBlock
        )
        bindings.positionBuilder(builder, at: useVirtualBlock)
        let functionPointerType = bindings.pointerType(calleeFunction.type)
        let fptr = bindings.buildIntToPtr(
            builder,
            value: fptrRaw,
            type: functionPointerType,
            name: "lookup_fptr_\(instructionIndex)"
        )

        var callArguments = virtualCallArguments
        var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
        if shouldAppendThrownChannel {
            if usesThrownChannel {
                let thrownSlot = stringAggregateBridge.buildEntrySlot(name: "vthrown_slot_\(instructionIndex)")
                if let thrownSlot {
                    _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                    callArguments.append(thrownSlot)
                    thrownSlotPointer = thrownSlot
                } else {
                    callArguments.append(nullThrownPointer)
                }
            } else {
                callArguments.append(nullThrownPointer)
            }
        }

        let vCallValue = bindings.buildCall(
            builder,
            functionType: calleeFunction.type,
            callee: fptr ?? calleeFunction.value,
            arguments: callArguments,
            name: "vcall_\(instructionIndex)"
        )
        if let result, let vCallValue {
            rawResultValues[result.rawValue] = vCallValue
        }
        _ = bindings.buildBr(builder, destination: mergeBlock)

        bindings.positionBuilder(builder, at: fallbackBlock)
        if let trapFn = declareExternalFunction(named: "kk_dispatch_error", argumentCount: 0, appendThrownChannel: false) {
            _ = bindings.buildCall(builder, functionType: trapFn.type, callee: trapFn.value, arguments: [], name: "trap_\(instructionIndex)")
        }
        _ = bindings.buildUnreachable(builder)

        bindings.positionBuilder(builder, at: mergeBlock)
        currentBlock = mergeBlock
        let mergedValue: LLVMCAPIBindings.LLVMValueRef
        if isThrowableMessageVirtualGetter,
           let result,
           let vCallValue
        {
            mergedValue = isStringAggregateExpr(result)
                ? stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                    vCallValue,
                    suffix: "\(instructionIndex)_virtual_throwable_message"
                ) ?? vCallValue
                : vCallValue
        } else if isAnyToStringRawABISlot,
           let result,
           let vCallValue
        {
            // The raw slot returned an `Int` string handle; a
            // String-typed result needs the flat aggregate.
            mergedValue = isStringAggregateExpr(result)
                ? stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                    vCallValue,
                    suffix: "\(instructionIndex)_virtual_any_toString"
                ) ?? vCallValue
                : vCallValue
        } else if isRuntimeCallbackRawABIVirtualCall,
           let result,
           isStringAggregateExpr(result),
           let vCallValue
        {
            mergedValue = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                vCallValue,
                suffix: "\(instructionIndex)_virtual_callback_result"
            ) ?? vCallValue
        } else if isInternalCall,
                  let result,
                  let resultExprType = module.arena.exprType(result),
                  let vCallValue,
                  let calleeKIRFunction
        {
            mergedValue = coerceStringValueForType(
                vCallValue,
                from: calleeKIRFunction.returnType,
                to: resultExprType,
                suffix: "\(instructionIndex)_virtual_internal_result"
            )
        } else if let result,
                  let resultExprType = module.arena.exprType(result),
                  let vCallValue,
                  stringAggregateBridge.isStringAggregateType(resultExprType) != bindings.isAggregateStructValue(vCallValue)
        {
            // The emitted callee ABI and the result's expected
            // representation can disagree on string-aggregate-ness for
            // itable or source-backed virtual calls — e.g. a flat
            // aggregate getter result consumed as the raw i64 handle by
            // a generic caller. Normalize by the value's actual shape.
            if stringAggregateBridge.isStringAggregateType(resultExprType) {
                mergedValue = stringAggregateBridge.bridgeRuntimeRawToStringAggregate(
                    vCallValue,
                    suffix: "\(instructionIndex)_virtual_result"
                ) ?? vCallValue
            } else {
                mergedValue = stringAggregateBridge.bridgeStringAggregateToRuntimeRaw(
                    vCallValue,
                    suffix: "\(instructionIndex)_virtual_flat_result"
                ) ?? vCallValue
            }
        } else {
            mergedValue = vCallValue ?? zeroValue
        }
        storeResult(result, mergedValue)

        if usesThrownChannel {
            handleThrownSlot(thrownSlotPointer, thrownResult: thrownResult, instructionIndex: instructionIndex, namePrefix: "v")
        }
    }

}
