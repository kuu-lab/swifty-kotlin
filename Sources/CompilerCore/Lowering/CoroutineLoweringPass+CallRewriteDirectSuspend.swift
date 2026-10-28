
extension CoroutineLoweringPass {
    func suspendWrapperValueClassResultUnboxing(
        for resultType: TypeID,
        using rewrite: SuspendRewriteContext
    ) -> (callee: InternedString, classSymbol: SymbolID?)? {
        guard let sema = rewrite.ctx.sema else {
            return nil
        }

        let resultKind = sema.types.kind(of: resultType)
        if let classSymbol = nullableUnderlyingValueClassSymbol(
            of: resultKind,
            types: sema.types,
            symbols: sema.symbols
        ) {
            return (rewrite.ctx.interner.intern("kk_value_class_unbox"), classSymbol)
        }

        guard case let .classType(classType) = resultKind,
              classType.nullability == .nonNull,
              let classSymbol = sema.symbols.symbol(classType.classSymbol),
              classSymbol.flags.contains(.valueType)
        else {
            return nil
        }

        let underlyingKind = resolveValueClassKind(
            resultKind,
            types: sema.types,
            symbols: sema.symbols
        )
        guard let unboxCallee = BoxingCalleeTable(interner: rewrite.ctx.interner).unboxCallee(
            for: underlyingKind,
            requireNonNull: true,
            preferStaticPrimitive: true
        ) else {
            return nil
        }
        return (unboxCallee, nil)
    }

    func rewriteSuspendFunctionValueCreation(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        let name = rewrite.ctx.interner.resolve(call.callee)
        guard name.hasPrefix("kk_function_create_"),
              let arity = Int(name.dropFirst("kk_function_create_".count)),
              call.arguments.count == 2,
              let original = symbolReference(
                  for: call.arguments[0], module: rewrite.module, propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[original]
        else { return nil }

        let entryPointSymbol: SymbolID
        if let thunk = rewrite.launcherThunkByOriginalSymbol[original] {
            entryPointSymbol = thunk.symbol
        } else if rewrite.module.arena.function(for: original)?.params.isEmpty == true {
            // A zero-argument suspend function already has the continuation-only
            // ABI after lowering, so its lowered entry point needs no launcher thunk.
            entryPointSymbol = loweredTarget.symbol
        } else {
            return nil
        }

        let entry = rewrite.module.arena.appendExpr(.symbolRef(entryPointSymbol), type: rewrite.intType)
        let arityExpr = rewrite.module.arena.appendExpr(.intLiteral(Int64(arity)), type: rewrite.intType)
        return [
            .constValue(result: entry, value: .symbolRef(entryPointSymbol)),
            .constValue(result: arityExpr, value: .intLiteral(Int64(arity))),
            .call(
                callee: rewrite.ctx.interner.intern("kk_suspend_function_create"),
                arguments: call.arguments + [arityExpr, entry], result: call.result,
                canThrow: false
            ),
        ]
    }

    func rewriteDirectSuspendCall(
        call: CallRewriteInput,
        callerContinuationSymbol: SymbolID?,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard let loweredTarget = resolveLoweredTarget(
            symbol: call.symbol,
            callee: call.callee,
            arity: call.arguments.count,
            using: rewrite
        ) else {
            return nil
        }
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        // Synthetic KIR fixtures and non-suspend callers (such as itable
        // bridges) do not carry a lowered caller continuation. Route them
        // through kk_coroutine_call_suspend_wrapper, which binds the child
        // continuation to the ambient RuntimeContinuationState.current caller
        // (or runs the child to completion when none exists) so a suspended
        // callee's completion still reaches the caller's suspend point; a bare
        // entry-point call would orphan the child continuation.
        guard let callerContinuationSymbol else {
            // Restore a value-class result from the erased continuation
            // completion before an itable bridge boxes it for its slot.
            let resultUnboxing = call.result
                .flatMap { rewrite.module.arena.exprType($0) }
                .flatMap { suspendWrapperValueClassResultUnboxing(for: $0, using: rewrite) }
            let wrapperResult: KIRExprID?
            if resultUnboxing != nil,
               let resultType = rewrite.anyType ?? rewrite.ctx.sema?.types.nullableAnyType
            {
                wrapperResult = rewrite.module.arena.appendTemporary(type: resultType)
            } else {
                wrapperResult = call.result
            }
            let continuationTemp = rewrite.module.arena.appendTemporary(
                type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
            )
            var instructions: [KIRInstruction] = [
                .constValue(
                    result: continuationFunctionID,
                    value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
                ),
                .call(
                    callee: rewrite.continuationFactory,
                    arguments: [continuationFunctionID],
                    result: continuationTemp,
                    canThrow: false
                ),
            ]
            let entryPointSymbol: SymbolID
            if call.arguments.isEmpty {
                entryPointSymbol = loweredTarget.symbol
            } else {
                let originalSymbol = call.symbol
                    ?? rewrite.originalByLoweredName[loweredTarget.name]?.original
                guard let originalSymbol,
                      let thunk = rewrite.launcherThunkByOriginalSymbol[originalSymbol]
                else {
                    return nil
                }
                entryPointSymbol = thunk.symbol
                for (index, argumentExpr) in call.arguments.enumerated() {
                    let slotExpr = rewrite.module.arena.appendExpr(
                        .intLiteral(Int64(index)),
                        type: rewrite.intType
                    )
                    instructions.append(
                        .call(
                            callee: rewrite.launcherArgSetCallee,
                            arguments: [continuationTemp, slotExpr, argumentExpr],
                            result: nil,
                            canThrow: false
                        )
                    )
                }
            }
            let entryPointExpr = rewrite.module.arena.appendExpr(
                .symbolRef(entryPointSymbol),
                type: rewrite.intType
            )
            instructions.append(
                .call(
                    callee: rewrite.ctx.interner.intern("kk_coroutine_call_suspend_wrapper"),
                    arguments: [entryPointExpr, continuationTemp],
                    result: wrapperResult,
                    canThrow: true,
                    thrownResult: call.thrownResult,
                    isSuperCall: call.isSuperCall
                )
            )
            if resultUnboxing != nil, let wrapperResult, let anyType = rewrite.anyType {
                let suspendedExpr = rewrite.module.arena.appendTemporary(type: anyType)
                instructions.append(.call(
                    callee: rewrite.ctx.interner.intern("kk_coroutine_suspended"),
                    arguments: [],
                    result: suspendedExpr,
                    canThrow: false
                ))
                // The erased wrapper result carries COROUTINE_SUSPENDED unchanged.
                // Preserve it before interpreting the word as a value-class payload.
                instructions.append(.returnIfEqual(lhs: wrapperResult, rhs: suspendedExpr))
            }
            if let callResult = call.result, let resultUnboxing, let wrapperResult {
                if let classSymbol = resultUnboxing.classSymbol,
                   let sema = rewrite.ctx.sema
                {
                    emitValueClassUnboxCall(
                        value: wrapperResult,
                        classSymbol: classSymbol,
                        result: callResult,
                        resultType: rewrite.module.arena.exprType(callResult),
                        types: sema.types,
                        symbols: sema.symbols,
                        interner: rewrite.ctx.interner,
                        arena: rewrite.module.arena,
                        into: &instructions
                    )
                } else {
                    instructions.append(.call(
                        callee: resultUnboxing.callee,
                        arguments: [wrapperResult],
                        result: callResult,
                        canThrow: false
                    ))
                }
            }
            return instructions
        }

        // STDLIB-CORO-BUG-01: a direct call from one suspend function's body to
        // another must relay the callee's completion back into this function's
        // own suspend point through kk_coroutine_call_direct_suspend.
        let childContinuationTemp = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        var instructions: [KIRInstruction] = [
            .constValue(
                result: continuationFunctionID,
                value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
            ),
            .call(
                callee: rewrite.continuationFactory,
                arguments: [continuationFunctionID],
                result: childContinuationTemp,
                canThrow: false
            ),
        ]

        // A suspend function with parameters is invoked through its launcher
        // thunk (the same adapter launch/async/runBlocking use), which reads
        // the real arguments back out of the child continuation's launcher-arg
        // storage. A 0-arg suspend function's lowered form already matches the
        // (continuation) -> Int entry-point shape directly.
        let entryPointSymbol: SymbolID
        if call.arguments.isEmpty {
            entryPointSymbol = loweredTarget.symbol
        } else {
            let originalSymbol = call.symbol ?? rewrite.originalByLoweredName[loweredTarget.name]?.original
            guard let originalSymbol,
                  let thunk = rewrite.launcherThunkByOriginalSymbol[originalSymbol]
            else {
                return nil
            }
            entryPointSymbol = thunk.symbol
            for (index, argumentExpr) in call.arguments.enumerated() {
                let slotExpr = rewrite.module.arena.appendExpr(
                    .intLiteral(Int64(index)),
                    type: rewrite.intType
                )
                instructions.append(
                    .call(
                        callee: rewrite.launcherArgSetCallee,
                        arguments: [childContinuationTemp, slotExpr, argumentExpr],
                        result: nil,
                        canThrow: false
                    )
                )
            }
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        let callerContinuationExpr = rewrite.module.arena.appendExpr(
            .symbolRef(callerContinuationSymbol),
            type: rewrite.anyType
        )
        instructions.append(
            .call(
                callee: rewrite.directSuspendCallCallee,
                arguments: [entryPointExpr, childContinuationTemp, callerContinuationExpr],
                result: call.result,
                canThrow: false,
                // The runtime wrapper reports child failures through the
                // caller continuation rather than the native thrown channel.
                // Keep the original slot as state-machine metadata so a
                // resumed exception is routed through the enclosing try.
                thrownResult: call.thrownResult,
                isSuperCall: call.isSuperCall
            )
        )
        return instructions
    }

    func resolveLoweredTarget(
        symbol: SymbolID?,
        callee: InternedString,
        arity: Int,
        using rewrite: SuspendRewriteContext
    ) -> LoweredSuspendFunction? {
        // Source-backed SequenceScope declarations provide the signature for
        // boxing, but builder bridges already implement their suspension ABI.
        // Rebinding them to the source suspend body would discard each yield.
        guard callee != rewrite.sequenceBuilderYieldCallee,
              callee != rewrite.sequenceBuilderYieldAllCallee,
              callee != rewrite.ctx.interner.intern("__kk_deep_recursive_scope_callRecursive"),
              callee != rewrite.ctx.interner.intern("__kk_deep_recursive_function_callRecursive")
        else { return nil }
        if let symbol {
            if let loweredBySymbol = rewrite.loweredBySymbol[symbol] {
                return loweredBySymbol
            }
            // Name/arity fallback is only valid for unresolved/runtime calls.
            // A resolved non-suspend declaration must not be rebound to the
            // unique suspend function with the same name (for example,
            // kotlin.ranges.toList versus Flow.toList after KSP-499).
            if let signature = rewrite.ctx.sema?.symbols.functionSignature(for: symbol),
               !signature.isSuspend
            {
                return nil
            }
        }
        let byNameArityKey = SuspendCallLookupKey(name: callee, arity: arity)
        if let loweredByNameArity = rewrite.loweredByUniqueNameArity[byNameArityKey] {
            return loweredByNameArity
        }
        return rewrite.loweredByUniqueName[callee]
    }
}
