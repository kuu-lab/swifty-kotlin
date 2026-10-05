
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
        let nonNullCallableType = sema.types.makeNonNullable(callableType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCallableType) else {
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("\(namePrefix)_\(argExprID.rawValue)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        // Build value parameters including the receiver (if present).
        // For receiver-bearing function types like `DeepRecursiveScope<T,R>.(T) -> R`,
        // the receiver is stored in `functionType.receiver` and must be forwarded
        // as an explicit parameter so the adapter's ABI matches the runtime call site.
        var allValueTypes: [TypeID] = []
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
            guard param.type != normalizedLambdaParamType,
                  let unboxCallee
            else {
                callArguments.append(paramExpr)
                continue
            }
            let unboxedExpr = arena.appendTemporary(type: lambdaParamType)
            body.append(.call(
                symbol: nil,
                callee: unboxCallee,
                arguments: [paramExpr],
                result: unboxedExpr,
                canThrow: false,
                thrownResult: nil
            ))
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

        // Reference-returning callbacks (e.g. Comparable selectors) need boxes
        // even when the concrete callable already has a closure parameter.
        let adapterReturnType = erasedFunctionType.flatMap {
            functionValueBoxedReturnType(
                concreteReturnType: functionType.returnType,
                expectedReturnType: $0.returnType,
                sema: sema
            )
        } ?? functionType.returnType

        let callResult = arena.appendTemporary(type: functionType.returnType
        )
        let canThrow = callableRequiresThrownChannel(callableInfo.symbol, arena: arena)
        body.append(.call(
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            arguments: callArguments,
            result: callResult,
            canThrow: canThrow,
            thrownResult: nil
        ))

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

    func functionValueBoxedReturnType(
        concreteReturnType: TypeID,
        expectedReturnType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        guard isNonNullValueRepresentationType(concreteReturnType, sema: sema) else {
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

    /// True for types represented as an erased `Any` handle at runtime: type
    /// parameters and `Any`/`Any?`.
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
