
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
                && isNonNullPrimitiveType(type, sema: sema)
            return KIRParameter(
                symbol: SymbolID(rawValue: Int32(clamping: symbolIDOffsetBase - Int64(argExprID.rawValue) * 16 - Int64(index))),
                type: isErasedPrimitiveParam ? sema.types.anyType : type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        var callArguments = appendCallableCaptureLoads(
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
            guard param.type != lambdaParamType,
                  let unboxCallee = boxingCalleeTable.unboxCallee(
                      for: lambdaParamType, types: sema.types, requireNonNull: true
                  )
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

        let callResult = arena.appendTemporary(type: functionType.returnType
        )
        body.append(.call(
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            arguments: callArguments,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))

        switch sema.types.kind(of: functionType.returnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)

        // Declaring an erased primitive result as `Any` makes ABILoweringPass
        // box the returned value, so `Double`/`Char` results keep their identity
        // once the generic caller stores them into an erased slot.
        let adapterReturnType: TypeID = {
            guard let erasedReturnType = erasedFunctionType?.returnType,
                  isErasedRepresentationType(erasedReturnType, sema: sema),
                  isNonNullPrimitiveType(functionType.returnType, sema: sema)
            else {
                return functionType.returnType
            }
            return sema.types.anyType
        }()

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

    /// True for types represented as an erased `Any` handle at runtime: type
    /// parameters and `Any`/`Any?`.
    private func isErasedRepresentationType(_ type: TypeID, sema: SemaModule) -> Bool {
        if case .typeParam = sema.types.kind(of: type) { return true }
        let nonNull = sema.types.makeNonNullable(type)
        return nonNull == sema.types.anyType
    }

    private func isNonNullPrimitiveType(_ type: TypeID, sema: SemaModule) -> Bool {
        if case .primitive(_, .nonNull) = sema.types.kind(of: type) { return true }
        return false
    }
}
