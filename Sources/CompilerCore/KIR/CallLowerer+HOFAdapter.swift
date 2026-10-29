
extension CallLowerer {
    func makeCollectionHOFCallableAdapter(
        callableInfo: KIRCallableValueInfo,
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        namePrefix: String,
        symbolIDOffsetBase: Int64,
        erasedFunctionType: FunctionType? = nil
    ) -> KIRCallableValueInfo? {
        let callableType = arena.exprType(loweredArgID) ?? sema.bindings.exprTypes[argExprID] ?? sema.types.anyType
        guard let functionType = callableFunctionType(
            for: callableType,
            matching: erasedFunctionType,
            sema: sema
        ) else {
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("\(namePrefix)_\(argExprID.rawValue)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        // For receiver-bearing function types like `DeepRecursiveScope<T,R>.(T) -> R`,
        // the receiver is stored in `functionType.receiver` and must be forwarded
        // as an explicit parameter so the adapter's ABI matches the runtime call site.
        var allValueTypes = functionType.contextReceivers
        if let receiverType = functionType.receiver {
            allValueTypes.append(receiverType)
        }
        allValueTypes.append(contentsOf: functionType.params)

        // When the callee declares the parameter with erased types -- e.g.
        // `fun <T, R> Array<T>.map(transform: (T) -> R)` -- the values crossing
        // the function-value ABI are `Any` handles, while the lambda literal was
        // compiled against the instantiated types (`(Double) -> Double`). The
        // adapter is that erasure boundary: it keeps the erased signature and
        // converts on both sides, so a boxed element reaches `{ it * 2 }` as a
        // raw `Double` and the raw result is boxed again before the generic
        // caller stores it into a `List<R>`.
        var erasedValueTypes: [TypeID] = []
        if let erasedFunctionType {
            erasedValueTypes.append(contentsOf: erasedFunctionType.contextReceivers)
            if erasedFunctionType.receiver != nil, functionType.receiver != nil {
                erasedValueTypes.append(erasedFunctionType.receiver ?? sema.types.anyType)
            }
            erasedValueTypes.append(contentsOf: erasedFunctionType.params)
        }
        func erasedValueType(at index: Int) -> TypeID? {
            guard erasedValueTypes.indices.contains(index) else { return nil }
            let erased = erasedValueTypes[index]
            guard isErasedRepresentationType(erased, sema: sema) else { return nil }
            return erased
        }

        let valueParams: [KIRParameter] = allValueTypes.enumerated().map { index, type in
            let isErasedPrimitiveParam = erasedValueType(at: index) != nil
                && (isNonNullValueRepresentationType(type, sema: sema)
                    || isNonNullEnumType(type, sema: sema))
            return KIRParameter(
                symbol: SymbolID(rawValue: Int32(clamping: symbolIDOffsetBase - Int64(argExprID.rawValue) * 16 - Int64(index))),
                type: isErasedPrimitiveParam ? sema.types.anyType : type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        var callArguments = callableInfo.hasClosureParam ? [closureExpr] : appendCallableCaptureLoads(
            callableInfo: callableInfo,
            closureExpr: closureExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )

        let boxingCalleeTable = BoxingCalleeTable(interner: interner)
        for (index, param) in valueParams.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            let lambdaParamType = allValueTypes[index]
            var forwardedParamExpr = paramExpr
            var emittedBoundaryCheckcast = false
            if let checkType = kirCheckableCastErasure(of: lambdaParamType, sema: sema),
               kirErasedBoundaryCheckable(checkType, sema: sema)
            {
                // KUU-3535: this adapter is the erased FunctionN invoke
                // boundary — the argument arrives as raw ABI bits that may
                // carry the wrong type (e.g. `extract(any as T)` with an
                // unbounded erasure). Emit the same checkcast Kotlin/JVM's
                // invoke bridge performs so a mismatch throws a catchable
                // ClassCastException instead of trapping inside the callee.
                let erasedOperand = arena.appendTemporary(type: sema.types.nullableAnyType)
                body.append(.copy(from: paramExpr, to: erasedOperand))
                let typeToken = driver.exprLowerer.lowerTypeCheckTokenExpr(
                    targetType: checkType,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &body
                )
                let checked = arena.appendTemporary(type: param.type)
                body.append(.call(
                    callee: interner.intern("kk_op_cast"),
                    arguments: [erasedOperand, typeToken],
                    result: checked,
                    canThrow: true
                ))
                forwardedParamExpr = checked
                emittedBoundaryCheckcast = true
            }
            if let valueClassSymbol = nullableUnderlyingValueClassSymbol(
                of: sema.types.kind(of: lambdaParamType),
                types: sema.types,
                symbols: sema.symbols
            )
            {
                // Erased generic callback slots carry nullable-underlying
                // value classes as nominal boxes; the typed lambda expects
                // the raw value-class payload.
                let unboxedExpr = arena.appendTemporary(type: lambdaParamType)
                emitValueClassUnboxCall(
                    value: forwardedParamExpr,
                    classSymbol: valueClassSymbol,
                    result: unboxedExpr,
                    types: sema.types,
                    symbols: sema.symbols,
                    interner: interner,
                    arena: arena,
                    into: &body
                )
                callArguments.append(unboxedExpr)
                continue
            }
            let lambdaParamKind = resolveValueClassKind(
                sema.types.kind(of: lambdaParamType),
                types: sema.types,
                symbols: sema.symbols
            )
            let normalizedLambdaParamType = sema.types.make(lambdaParamKind)
            let unboxCallee: InternedString? = {
                if isNonNullEnumType(lambdaParamType, sema: sema) {
                    return ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner)
                }
                return boxingCalleeTable.unboxCallee(
                    for: lambdaParamKind, requireNonNull: true
                )
            }()
            // A boundary checkcast returns its operand — which argument
            // normalization may have boxed to make the runtime check
            // meaningful — so a non-null primitive lambda parameter still
            // needs the unbox even when the adapter declares the same type.
            // Otherwise the tagged box leaks into the callee's raw
            // arithmetic (KUU-3689).
            let checkcastNeedsUnbox: Bool = {
                guard emittedBoundaryCheckcast,
                      case .primitive(_, .nonNull) = lambdaParamKind
                else { return false }
                return true
            }()
            guard param.type != normalizedLambdaParamType || checkcastNeedsUnbox,
                  let unboxCallee
            else {
                callArguments.append(forwardedParamExpr)
                continue
            }
            let unboxedExpr = arena.appendTemporary(type: lambdaParamType)
            body.append(.call(callee: unboxCallee, arguments: [forwardedParamExpr], result: unboxedExpr, canThrow: false))
            callArguments.append(unboxedExpr)
        }

        if !callableInfo.hasClosureParam,
           functionType.receiver != nil,
           sema.bindings.isCoroutineLauncherLambdaExpr(argExprID)
        {
            let captureCount = callableInfo.captureArguments.count
            callArguments = Array(callArguments.dropFirst(captureCount))
                + Array(callArguments.prefix(captureCount))
        }

        // Use the emitted function's return type: a callable reference can be
        // contextually typed as `(T) -> R` while its entry point returns a
        // concrete primitive such as `Int`.
        let callableReturnType = arena.function(for: callableInfo.symbol)?.returnType
            ?? functionType.returnType

        // Reference-returning callbacks (e.g. Comparable selectors) need boxes
        // even when the concrete callable already has a closure parameter.
        let adapterReturnType = erasedFunctionType.flatMap {
            functionValueBoxedReturnType(
                concreteReturnType: functionType.returnType,
                expectedReturnType: $0.returnType,
                sema: sema
            )
        } ?? functionType.returnType

        // Generic callbacks may already return an erased, boxed value. The
        // emitted callable ABI also preserves that distinction here.
        let callResult = arena.appendTemporary(type: callableReturnType)
        let canThrow = callableRequiresThrownChannel(callableInfo.symbol, arena: arena)
        body.append(.call(symbol: callableInfo.symbol, callee: callableInfo.callee, arguments: callArguments, result: callResult, canThrow: canThrow))

        switch sema.types.kind(of: adapterReturnType) {
        case .unit, .nothing(.nonNull):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)

        // `functionType.isSuspend` reflects the *expected* (contextual) type the
        // argument lambda was checked against -- e.g. a plain `(T) -> R)` HOF
        // parameter like `List.map`'s `transform`. A lambda literal passed there
        // can still contain suspend calls in its body (Kotlin allows this for
        // `inline` HOFs; KSwiftK currently permits it more broadly), in which case
        // the lambda's own compiled function is genuinely suspend even though its
        // contextual type is not. If the adapter itself isn't marked suspend to
        // match, CoroutineLoweringPass never rewrites its `.call` below into a
        // suspend call, so the callee reads an uninitialized "continuation" and
        // crashes. Prefer the callee's real suspend-ness when known.
        let calleeIsSuspend = arena.function(for: callableInfo.symbol)?.isSuspend ?? functionType.isSuspend
        let adapterDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: adapterSymbol,
                    name: adapterName,
                    params: [closureParam] + valueParams,
                    returnType: adapterReturnType,
                    body: body,
                    isSuspend: calleeIsSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        return KIRCallableValueInfo(
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: callableInfo.captureArguments,
            hasClosureParam: true
        )
    }

    func callableFunctionType(
        for type: TypeID,
        matching expectedFunctionType: FunctionType? = nil,
        sema: SemaModule
    ) -> FunctionType? {
        let nonNullType = sema.types.makeNonNullable(type)
        switch sema.types.kind(of: nonNullType) {
        case let .functionType(functionType):
            return functionType
        case let .classType(classType):
            if let functionType = sema.types.nominalFunctionType(for: nonNullType) {
                return functionType
            }
            guard let expectedFunctionType else { return nil }
            let arity = expectedFunctionType.contextReceivers.count
                + (expectedFunctionType.receiver == nil ? 0 : 1)
                + expectedFunctionType.params.count
            guard let inheritedFunctionType = sema.types.inheritedFunctionInterfaceClassType(
                of: classType,
                arity: arity,
                isSuspend: expectedFunctionType.isSuspend
            ) else {
                return nil
            }
            return sema.types.nominalFunctionType(
                for: sema.types.make(.classType(inheritedFunctionType))
            )
        default:
            return nil
        }
    }

    func functionValueBoxedReturnType(
        concreteReturnType: TypeID,
        expectedReturnType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        if nullableUnderlyingValueClassSymbol(
            of: sema.types.kind(of: concreteReturnType),
            types: sema.types,
            symbols: sema.symbols
        ) != nil,
            isErasedRepresentationType(expectedReturnType, sema: sema)
        {
            // A nullable-underlying value class uses its payload as the direct
            // representation, so an erased callback result needs the nominal
            // box to preserve the wrapper's non-null identity.
            return sema.types.anyType
        }
        // Unit also needs a value across an erased return boundary. Keeping
        // the adapter void would discard the lambda's boxed Unit singleton.
        guard sema.types.kind(of: concreteReturnType) == .unit
            || isNonNullValueRepresentationType(concreteReturnType, sema: sema) else {
            return nil
        }
        if isErasedRepresentationType(expectedReturnType, sema: sema) {
            return sema.types.anyType
        }
        if case .classType = sema.types.kind(of: expectedReturnType),
           !isNonNullValueRepresentationType(expectedReturnType, sema: sema),
           !isNonNullEnumType(expectedReturnType, sema: sema)
        {
            return expectedReturnType
        }
        return nil
    }

    /// Splits a `transform` callable bound for a `__kk_list_*_transform`
    /// runtime bridge into its `(fnPtr, closureRaw)` pair, first wrapping the
    /// callable in an erased-ABI adapter when its concrete return is a value
    /// type. The bridges append the callback's raw return into `List<R>`
    /// verbatim, and `R` elements are `Any`-handled — so a raw Boolean/Char/Int
    /// result would surface as `0`/`1`/code points instead of `true`/`a`
    /// (KUU-1434). Reference-returning callables already deliver object
    /// handles and pass through unchanged.
    ///
    /// `existingEnvPtrID` is the closureRaw slot that already belongs to
    /// `callableArgID` when the caller received a pre-split pair (e.g. via
    /// `addCollectionHOFClosureArguments`). Opaque callables that carry no
    /// compile-time `callableValueInfo` — such as a `kk_function_create_N`
    /// box resolved through `kk_function_value_fn_ptr`/`_closure_raw` — must
    /// keep that existing pair: re-running the runtime resolution on an
    /// already-resolved fnPtr loses the captured environment.
    func splitErasedTransformBridgeArgument(
        _ callableArgID: KIRExprID,
        existingEnvPtrID: KIRExprID? = nil,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (fnPtrExpr: KIRExprID, envPtrExpr: KIRExprID) {
        if let callableInfo = driver.ctx.callableValueInfo(for: callableArgID),
           let callableType = arena.exprType(callableArgID) ?? sema.bindings.exprTypes[argExprID],
           case let .functionType(concreteFunctionType) = sema.types.kind(of: sema.types.makeNonNullable(callableType)),
           functionValueBoxedReturnType(
               concreteReturnType: concreteFunctionType.returnType,
               expectedReturnType: sema.types.anyType,
               sema: sema
           ) != nil,
           let adapted = makeCollectionHOFCallableAdapter(
               callableInfo: callableInfo,
               loweredArgID: callableArgID,
               argExprID: argExprID,
               sema: sema,
               arena: arena,
               interner: interner,
               namePrefix: "kk_transform_result_adapter",
               symbolIDOffsetBase: -730_000,
               erasedFunctionType: FunctionType(
                   receiver: concreteFunctionType.receiver.map { _ in sema.types.anyType },
                   params: concreteFunctionType.params.map { _ in sema.types.anyType },
                   returnType: sema.types.anyType,
                   isSuspend: concreteFunctionType.isSuspend,
                   isCallableReference: concreteFunctionType.isCallableReference
               )
           )
        {
            let adaptedExpr = arena.appendExpr(
                .symbolRef(adapted.symbol),
                type: arena.exprType(callableArgID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: adaptedExpr, value: .symbolRef(adapted.symbol)))
            driver.ctx.registerCallableValue(
                adaptedExpr,
                symbol: adapted.symbol,
                callee: adapted.callee,
                captureArguments: adapted.captureArguments,
                hasClosureParam: adapted.hasClosureParam
            )
            return splitCallableLambdaArgument(
                adaptedExpr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        if let existingEnvPtrID {
            return (callableArgID, existingEnvPtrID)
        }
        return splitCallableLambdaArgument(
            callableArgID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func isErasedRepresentationType(_ type: TypeID, sema: SemaModule) -> Bool {
        if case .typeParam = sema.types.kind(of: type) { return true }
        let nonNull = sema.types.makeNonNullable(type)
        return nonNull == sema.types.anyType
    }

    private func isNonNullValueRepresentationType(_ type: TypeID, sema: SemaModule) -> Bool {
        let kind = resolveValueClassKind(
            sema.types.kind(of: type),
            types: sema.types,
            symbols: sema.symbols
        )
        if case .primitive(_, .nonNull) = kind { return true }
        if case .stringStruct(.nonNull) = kind { return true }
        return false
    }

    private func isNonNullEnumType(_ type: TypeID, sema: SemaModule) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              classType.nullability == .nonNull,
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.kind == .enumClass
    }
}
