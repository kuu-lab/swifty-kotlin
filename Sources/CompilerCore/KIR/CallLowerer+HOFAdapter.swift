
extension CallLowerer {
    func makeCollectionHOFCallableAdapter(
        callableInfo: KIRCallableValueInfo,
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        namePrefix: String,
        symbolIDOffsetBase: Int64
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
        let valueParams: [KIRParameter] = allValueTypes.enumerated().map { index, type in
            KIRParameter(
                symbol: SymbolID(rawValue: Int32(clamping: symbolIDOffsetBase - Int64(argExprID.rawValue) * 16 - Int64(index))),
                type: type
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

        for param in valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            callArguments.append(paramExpr)
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
                    returnType: functionType.returnType,
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
}
