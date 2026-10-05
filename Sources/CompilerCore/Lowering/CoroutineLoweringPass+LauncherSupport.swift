
extension CoroutineLoweringPass {
    struct LauncherThunkSynthesisContext {
        let module: KIRModule
        let interner: StringInterner
        let sema: SemaModule?
        let anyType: TypeID?
        let intType: TypeID?
        let launcherArgGetCallee: InternedString
        let loweredBySymbol: [SymbolID: LoweredSuspendFunction]
        let continuationTypeByLoweredSymbol: [SymbolID: TypeID]
    }

    func synthesizeLauncherThunks(
        suspendFunctions: [KIRFunction],
        nextSyntheticSymbol: inout Int32,
        existingFunctionNames: inout Set<InternedString>,
        using synthesis: LauncherThunkSynthesisContext
    ) -> [SymbolID: LoweredSuspendFunction] {
        var launcherThunkByOriginalSymbol: [SymbolID: LoweredSuspendFunction] = [:]

        for suspendFunction in suspendFunctions where suspendFunction.params.count > 0 {
            guard let loweredTarget = synthesis.loweredBySymbol[suspendFunction.symbol] else {
                continue
            }
            let rawThunkName = synthesis.interner.intern(
                "kk_launcher_thunk_" + synthesis.interner.resolve(suspendFunction.name)
            )
            let thunkName = uniqueFunctionName(
                preferred: rawThunkName,
                existingFunctionNames: &existingFunctionNames,
                interner: synthesis.interner
            )
            let thunkSymbol = allocateSyntheticSymbol(
                &nextSyntheticSymbol,
                sema: synthesis.sema,
                interner: synthesis.interner
            )
            let thunkContParamSymbol = allocateSyntheticSymbol(
                &nextSyntheticSymbol,
                sema: synthesis.sema,
                interner: synthesis.interner
            )
            let contType = synthesis.continuationTypeByLoweredSymbol[loweredTarget.symbol]
                ?? synthesis.anyType ?? suspendFunction.returnType

            let thunkBody = buildLauncherThunkBody(
                suspendFunction: suspendFunction,
                loweredTarget: loweredTarget,
                thunkContParamSymbol: thunkContParamSymbol,
                module: synthesis.module,
                intType: synthesis.intType,
                contType: contType,
                launcherArgGetCallee: synthesis.launcherArgGetCallee
            )

            let thunkFunction = KIRFunction(
                symbol: thunkSymbol,
                name: thunkName,
                params: [KIRParameter(symbol: thunkContParamSymbol, type: contType)],
                returnType: contType,
                body: thunkBody,
                isSuspend: false,
                isInline: false
            )
            _ = synthesis.module.arena.appendDecl(.function(thunkFunction))
            launcherThunkByOriginalSymbol[suspendFunction.symbol] = (name: thunkName, symbol: thunkSymbol)
        }

        return launcherThunkByOriginalSymbol
    }

    func synthesizeSequenceBuilderReceiverThunks(
        suspendFunctions: [KIRFunction],
        nextSyntheticSymbol: inout Int32,
        existingFunctionNames: inout Set<InternedString>,
        using synthesis: LauncherThunkSynthesisContext
    ) -> [SymbolID: LoweredSuspendFunction] {
        var thunkByOriginalSymbol: [SymbolID: LoweredSuspendFunction] = [:]

        for suspendFunction in suspendFunctions where suspendFunction.params.count == 1 {
            guard let loweredTarget = synthesis.loweredBySymbol[suspendFunction.symbol] else {
                continue
            }
            let rawThunkName = synthesis.interner.intern(
                "kk_sequence_builder_thunk_" + synthesis.interner.resolve(suspendFunction.name)
            )
            let thunkName = uniqueFunctionName(
                preferred: rawThunkName,
                existingFunctionNames: &existingFunctionNames,
                interner: synthesis.interner
            )
            let thunkSymbol = allocateSyntheticSymbol(
                &nextSyntheticSymbol,
                sema: synthesis.sema,
                interner: synthesis.interner
            )
            let thunkContParamSymbol = allocateSyntheticSymbol(
                &nextSyntheticSymbol,
                sema: synthesis.sema,
                interner: synthesis.interner
            )
            let contType = synthesis.continuationTypeByLoweredSymbol[loweredTarget.symbol]
                ?? synthesis.anyType ?? suspendFunction.returnType
            let thunkBody = buildSequenceBuilderReceiverThunkBody(
                suspendFunction: suspendFunction,
                loweredTarget: loweredTarget,
                thunkContParamSymbol: thunkContParamSymbol,
                module: synthesis.module,
                intType: synthesis.intType,
                contType: contType,
                launcherArgGetCallee: synthesis.launcherArgGetCallee
            )

            let thunkFunction = KIRFunction(
                symbol: thunkSymbol,
                name: thunkName,
                params: [KIRParameter(symbol: thunkContParamSymbol, type: contType)],
                returnType: contType,
                body: thunkBody,
                isSuspend: false,
                isInline: false
            )
            _ = synthesis.module.arena.appendDecl(.function(thunkFunction))
            thunkByOriginalSymbol[suspendFunction.symbol] = (name: thunkName, symbol: thunkSymbol)
        }

        return thunkByOriginalSymbol
    }

    func buildSequenceBuilderReceiverThunkBody(
        suspendFunction: KIRFunction,
        loweredTarget: LoweredSuspendFunction,
        thunkContParamSymbol: SymbolID,
        module: KIRModule,
        intType: TypeID?,
        contType: TypeID,
        launcherArgGetCallee: InternedString
    ) -> [KIRInstruction] {
        let contRef = module.arena.appendExpr(
            .symbolRef(thunkContParamSymbol),
            type: contType
        )
        let builderSlotExpr = module.arena.appendExpr(
            .intLiteral(1),
            type: intType
        )
        let builderResult = module.arena.appendTemporary(type: suspendFunction.params[0].type
        )
        let callResult = module.arena.appendTemporary(type: contType
        )
        return [
            .call(
                symbol: nil,
                callee: launcherArgGetCallee,
                arguments: [contRef, builderSlotExpr],
                result: builderResult,
                canThrow: false,
                thrownResult: nil
            ),
            .call(
                symbol: loweredTarget.symbol,
                callee: loweredTarget.name,
                arguments: [builderResult, contRef],
                result: callResult,
                canThrow: true,
                thrownResult: nil
            ),
            .returnValue(callResult),
        ]
    }

    func buildLauncherThunkBody(
        suspendFunction: KIRFunction,
        loweredTarget: LoweredSuspendFunction,
        thunkContParamSymbol: SymbolID,
        module: KIRModule,
        intType: TypeID?,
        contType: TypeID,
        launcherArgGetCallee: InternedString
    ) -> [KIRInstruction] {
        var thunkBody: [KIRInstruction] = []
        let contRef = module.arena.appendExpr(
            .symbolRef(thunkContParamSymbol),
            type: contType
        )

        var callArgExprs: [KIRExprID] = []
        for paramIndex in 0 ..< suspendFunction.params.count {
            let slotExpr = module.arena.appendExpr(
                .intLiteral(Int64(paramIndex)),
                type: intType
            )
            let argResult = module.arena.appendTemporary(type: suspendFunction.params[paramIndex].type
            )
            thunkBody.append(
                .call(
                    symbol: nil,
                    callee: launcherArgGetCallee,
                    arguments: [contRef, slotExpr],
                    result: argResult,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            callArgExprs.append(argResult)
        }

        callArgExprs.append(contRef)
        let callResult = module.arena.appendTemporary(type: contType
        )
        thunkBody.append(
            .call(
                symbol: loweredTarget.symbol,
                callee: loweredTarget.name,
                arguments: callArgExprs,
                result: callResult,
                canThrow: true,
                thrownResult: nil
            )
        )
        thunkBody.append(.returnValue(callResult))
        return thunkBody
    }

    /// Returns `true` when `symbol` is one of the actual kotlinx.coroutines
    /// launcher declarations (`runBlocking`, `launch`, `async`, `produce`).
    /// This lets us distinguish user-defined methods that happen to share a name
    /// (e.g. `Producer.produce`) from real coroutine builders.
    func isKnownCoroutineLauncherSymbol(_ symbol: SymbolID, using rewrite: SuspendRewriteContext) -> Bool {
        guard let sema = rewrite.ctx.sema,
              let sym = sema.symbols.symbol(symbol),
              !sym.fqName.isEmpty
        else {
            return false
        }
        // KSP-1573: the bundled `CoroutineScope.produce` extension shares the
        // `kotlinx.coroutines.channels.produce` fqName with the removed
        // synthetic launcher but is an ordinary function (its block is a
        // boxed suspend value, not a launcher thunk). Real launcher builders
        // are all synthetic; imported library declarations only look
        // synthetic because they carry no source declSite.
        if !sym.flags.contains(.synthetic) || sym.flags.contains(.importedLibrary) {
            return false
        }
        let interner = rewrite.ctx.interner
        let fqName = sym.fqName
        let lastName = interner.resolve(fqName[fqName.count - 1])
        guard lastName == "runBlocking"
           || lastName == "launch"
           || lastName == "async"
           || lastName == "produce"
        else {
            return false
        }
        let package = fqName.dropLast().map { interner.resolve($0) }.joined(separator: ".")
        return package == "kotlinx.coroutines" || package == "kotlinx.coroutines.channels"
    }

    /// Returns true when `symbol` is the suspend function of a lambda
    /// literal Sema marked as a coroutine launcher block (the literal arg of
    /// produce/actor/runBlocking-style builders) — the only lambdas lowered
    /// with the receiver-first `(receiver, cap0..capN)` param layout
    /// (LambdaLowerer's `receiverFirstLauncherABI` gate). The originating
    /// lambda's ExprID is recovered from its `kk_lambda_<exprID>` name;
    /// anything else (a stored suspend function value, a callable
    /// reference, a named suspend function) is capture-first and must take
    /// the boxed function-value path instead.
    func isCoroutineLauncherMarkedBlock(
        _ symbol: SymbolID,
        using rewrite: SuspendRewriteContext
    ) -> Bool {
        guard let sema = rewrite.ctx.sema,
              let function = rewrite.module.arena.function(for: symbol)
        else {
            return false
        }
        let name = rewrite.ctx.interner.resolve(function.name)
        let prefix = "kk_lambda_"
        guard name.hasPrefix(prefix),
              let exprRaw = Int32(name.dropFirst(prefix.count))
        else {
            return false
        }
        return sema.bindings.isCoroutineLauncherLambdaExpr(ExprID(rawValue: exprRaw))
    }

    /// STDLIB-CORO-001: Detect whether an expression has the synthetic
    /// `kotlinx.coroutines.CoroutineStart` enum type, used to disambiguate
    /// `launch(start = CoroutineStart.LAZY)` from `launch(Dispatchers.Default)`.
    func isCoroutineStartExpression(
        _ exprID: KIRExprID,
        using rewrite: SuspendRewriteContext
    ) -> Bool {
        guard let sema = rewrite.ctx.sema,
              let type = rewrite.module.arena.exprType(exprID),
              case let .classType(classType) = sema.types.kind(of: type)
        else {
            return false
        }
        guard let symbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }
        let interner = rewrite.ctx.interner
        let fqName = symbol.fqName
        guard fqName.count >= 3 else { return false }
        return interner.resolve(fqName[fqName.count - 1]) == "CoroutineStart"
            && interner.resolve(fqName[fqName.count - 3]) == "kotlinx"
            && interner.resolve(fqName[fqName.count - 2]) == "coroutines"
    }

    func rewriteLauncherCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        if call.callee == rewrite.ctx.interner.intern("kk_coroutine_scope_async") {
            return rewriteCoroutineScopeAsyncCall(
                call: call, symbolByExprRaw: symbolByExprRaw, using: rewrite
            )
        }
        // KSP-1573: `__kk_produce_launch(channel, block)` is the runtime
        // bridge emitted inside the bundled produce/actor bodies (their
        // kirbin expansion materializes the call inline at every call site).
        // A literal/resolvable suspend block rewrites into the launcher
        // continuation convention — channel in launcherArgs[0], captures in
        // the remaining slots — the same shape rewriteProduceLauncherCall
        // builds for the synthetic kk_produce path.
        if call.callee == rewrite.ctx.interner.intern("__kk_produce_launch") {
            return rewriteChannelProduceLaunchCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            )
        }

        // KSP-1583: `kk_test_run_blocking(context, timeout, block)` — the
        // extern `kotlinx.coroutines.test.runTest` itself, so the trailing
        // suspend literal reaches here from the user's call site. Same
        // dual-shape handling as `__kk_produce_launch`: a resolvable suspend
        // block rewrites into the launcher continuation convention (the
        // runtime mints the TestScope and binds it at launcherArgs[0],
        // captures in the remaining slots); a block held in a variable
        // falls through to the boxed-value cdecl.
        if call.callee == rewrite.ctx.interner.intern("kk_test_run_blocking") {
            return rewriteTestScopeRunBlockingCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            )
        }

        // `CoroutineScope.launch { }` is a receiver-bearing member call: the general
        // member-call emission path already prepended the receiver as arguments[0]
        // (see appendReceiverToMemberArguments), giving this a distinct callee name
        // from bare top-level `launch`/`launch(dispatcher)`, so it is handled by its
        // own dedicated rewrite rather than kxMiniLauncherRuntimeCallees below.
        if call.callee == rewrite.coroutineScopeLaunchCallee {
            return rewriteCoroutineScopeLaunchCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            )
        }

        guard let runtimeLauncherCallee = rewrite.kxMiniLauncherRuntimeCallees[call.callee]
        else {
            return nil
        }
        // A real source-backed function with a launcher name (e.g. a user-defined
        // `Producer.produce` method) is not a coroutine builder.
        if let symbol = call.symbol, !isKnownCoroutineLauncherSymbol(symbol, using: rewrite) {
            return nil
        }
        let produceCallee = rewrite.ctx.interner.intern("produce")
        let runtimeProduceCallee = rewrite.ctx.interner.intern("kk_produce")

        guard call.arguments.count >= 1 else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0001",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' expects at least one suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }

        // STDLIB-CORO-072: Check if the first argument is a dispatcher (not a suspend function).
        // launch(Dispatchers.IO) { } has the dispatcher as arguments[0] and the lambda as arguments[1].
        let firstArgSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        )
        let firstLowered = firstArgSymbol.flatMap { rewrite.loweredBySymbol[$0] }

        if firstLowered == nil && call.arguments.count >= 2 {
            let launchCallee = rewrite.ctx.interner.intern("launch")
            let asyncCallee = rewrite.ctx.interner.intern("async")

            // STDLIB-CORO-001: launch/async (start = CoroutineStart.X) overload.
            // Tested before the launch-only gate below, because `async` has a
            // start-mode overload but no dispatcher-aware one: falling through
            // to that gate would reject `async(start = ...)` outright.
            if call.callee == launchCallee || call.callee == asyncCallee,
               isCoroutineStartExpression(call.arguments[0], using: rewrite)
            {
                return rewriteStartModeLauncherCall(
                    startExpr: call.arguments[0],
                    suspendArgExpr: call.arguments[1],
                    extraArgs: Array(call.arguments.dropFirst(2)),
                    call: call,
                    symbolByExprRaw: symbolByExprRaw,
                    using: rewrite
                )
            }

            guard call.callee == launchCallee else {
                // Dispatcher-aware pattern is only valid for `launch`.
                rewrite.ctx.diagnostics.error(
                    "KSWIFTK-CORO-0002",
                    "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' requires a suspend function reference argument.",
                    range: nil
                )
                return [call.instruction]
            }

            // First argument is not a suspend function. Try to interpret it as a dispatcher.
            let dispatcherExpr = call.arguments[0]
            let suspendArgExpr = call.arguments[1]

            if let suspendSymbol = symbolReference(
                for: suspendArgExpr,
                module: rewrite.module,
                propagatedSymbols: symbolByExprRaw
            ), let loweredTarget = rewrite.loweredBySymbol[suspendSymbol] {
                let targetArity = rewrite.suspendFunctionArityBySymbol[suspendSymbol] ?? 0
                let extraArgs = Array(call.arguments.dropFirst(2))
                guard extraArgs.count == targetArity else {
                    rewrite.ctx.diagnostics.error(
                        "KSWIFTK-CORO-0003",
                        "Coroutine launcher 'launch' passed \(extraArgs.count) capture argument(s) but referenced suspend function expects \(targetArity).",
                        range: nil
                    )
                    return [call.instruction]
                }

                if targetArity == 0 {
                    return rewriteZeroArgDispatcherLauncherCall(
                        dispatcherExpr: dispatcherExpr,
                        loweredTarget: loweredTarget,
                        call: call,
                        using: rewrite
                    )
                }

                guard let thunk = rewrite.launcherThunkByOriginalSymbol[suspendSymbol] else {
                    assertionFailure("Internal compiler error: launcher thunk missing for dispatcher-aware launch")
                    return [call.instruction]
                }
                return rewriteArgBearingDispatcherLauncherCall(
                    dispatcherExpr: dispatcherExpr,
                    loweredTarget: loweredTarget,
                    thunk: thunk,
                    extraArgs: extraArgs,
                    call: call,
                    using: rewrite
                )
            }
            // Fall through to normal error path if we still cannot resolve.
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0002",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' requires a suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }

        guard let referencedSymbol = firstArgSymbol,
              let loweredTarget = firstLowered
        else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0002",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' requires a suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }

        let targetArity = rewrite.suspendFunctionArityBySymbol[referencedSymbol] ?? 0
        let extraArgs = Array(call.arguments.dropFirst())
        if call.callee == produceCallee || call.callee == runtimeProduceCallee {
            let expectedExtraArgs = max(0, targetArity - 1)
            guard extraArgs.count == expectedExtraArgs else {
                rewrite.ctx.diagnostics.error(
                    "KSWIFTK-CORO-0003",
                    "Coroutine launcher 'produce' passed \(extraArgs.count) argument(s) but referenced suspend function expects \(expectedExtraArgs) after reserving the produced channel receiver.",
                    range: nil
                )
                return [call.instruction]
            }

            guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol],
                  let runtimeWithContCallee = rewrite.kxMiniLauncherWithContCallees[call.callee]
            else {
                assertionFailure("Internal compiler error: launcher thunk or _with_cont callee missing for '\(rewrite.ctx.interner.resolve(call.callee))'")
                return [call.instruction]
            }

            return rewriteProduceLauncherCall(
                runtimeWithContCallee: runtimeWithContCallee,
                loweredTarget: loweredTarget,
                thunk: thunk,
                extraArgs: extraArgs,
                call: call,
                using: rewrite
            )
        }
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0003",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' passed \(extraArgs.count) argument(s) but referenced suspend function expects \(targetArity).",
                range: nil
            )
            return [call.instruction]
        }

        if targetArity == 0 {
            return rewriteZeroArgLauncherCall(
                runtimeLauncherCallee: runtimeLauncherCallee,
                loweredTarget: loweredTarget,
                call: call,
                using: rewrite
            )
        }

        guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol],
              let runtimeWithContCallee = rewrite.kxMiniLauncherWithContCallees[call.callee]
        else {
            assertionFailure("Internal compiler error: launcher thunk or _with_cont callee missing for '\(rewrite.ctx.interner.resolve(call.callee))'")
            return [call.instruction]
        }

        return rewriteArgBearingLauncherCall(
            runtimeWithContCallee: runtimeWithContCallee,
            loweredTarget: loweredTarget,
            thunk: thunk,
            extraArgs: extraArgs,
            call: call,
            using: rewrite
        )
    }

    // STDLIB-CORO-072: Rewrite launch(dispatcher) { } with no captures
    func rewriteZeroArgDispatcherLauncherCall(
        dispatcherExpr: KIRExprID,
        loweredTarget: LoweredSuspendFunction,
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let entryFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let runtimeCallee = rewrite.ctx.interner.intern("kk_kxmini_launch_with_dispatcher")

        return [
            .constValue(result: entryPointExpr, value: .symbolRef(loweredTarget.symbol)),
            .constValue(result: entryFunctionID, value: .intLiteral(Int64(loweredTarget.symbol.rawValue))),
            .call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [entryPointExpr, entryFunctionID, dispatcherExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            ),
        ]
    }

    // STDLIB-CORO-072: Rewrite launch(dispatcher) { captures } with captures
    func rewriteArgBearingDispatcherLauncherCall(
        dispatcherExpr: KIRExprID,
        loweredTarget: LoweredSuspendFunction,
        thunk: LoweredSuspendFunction,
        extraArgs: [KIRExprID],
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let runtimeCallee = rewrite.ctx.interner.intern("kk_kxmini_launch_with_dispatcher_and_cont")

        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        let thunkRefExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(
            .call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [thunkRefExpr, continuationExpr, dispatcherExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: nil
            )
        )
        return rewritten
    }

    // STDLIB-CORO-001: Rewrite launch/async (start = CoroutineStart.X) { block }.
    //
    // Kotlin's four start modes are not interchangeable. DEFAULT and ATOMIC
    // schedule the body right away (they differ only in whether a cancel before
    // the first suspension can still stop it, which this runtime does not model
    // separately), LAZY defers it until `start()`/`join()`/`await()`, and
    // UNDISPATCHED runs it inline on the calling thread up to the first
    // suspension. Every mode used to be routed to the lazy runtime, so
    // `launch(start = CoroutineStart.DEFAULT)` and `UNDISPATCHED` both silently
    // behaved as LAZY -- the body did not run at all until something joined it.
    //
    // `async` shares this rewrite, differing only in which runtime entry points
    // the start mode selects: its handles are `Deferred`s carrying the block's
    // result, so it has a parallel `kk_kxmini_async*` family.
    func rewriteStartModeLauncherCall(
        startExpr: KIRExprID,
        suspendArgExpr: KIRExprID,
        extraArgs: [KIRExprID],
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        guard let suspendSymbol = symbolReference(
            for: suspendArgExpr,
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ), let loweredTarget = rewrite.loweredBySymbol[suspendSymbol] else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0002",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' requires a suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }

        let targetArity = rewrite.suspendFunctionArityBySymbol[suspendSymbol] ?? 0
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0003",
                "Coroutine launcher '\(rewrite.ctx.interner.resolve(call.callee))' passed \(extraArgs.count) capture argument(s) but referenced suspend function expects \(targetArity).",
                range: nil
            )
            return [call.instruction]
        }

        let callees = coroutineStartRuntimeCallees(
            startExpr: startExpr,
            builderCallee: call.callee,
            symbolByExprRaw: symbolByExprRaw,
            using: rewrite
        )

        if targetArity == 0 {
            return rewriteZeroArgLauncherCall(
                runtimeLauncherCallee: callees.zeroArg,
                loweredTarget: loweredTarget,
                call: call,
                using: rewrite
            )
        }

        guard let thunk = rewrite.launcherThunkByOriginalSymbol[suspendSymbol] else {
            assertionFailure("Internal compiler error: launcher thunk missing for \(rewrite.ctx.interner.resolve(call.callee))(start:)")
            return [call.instruction]
        }
        return rewriteArgBearingLauncherCall(
            runtimeWithContCallee: callees.withCont,
            loweredTarget: loweredTarget,
            thunk: thunk,
            extraArgs: extraArgs,
            call: call,
            using: rewrite
        )
    }

    /// The runtime launchers implementing the `CoroutineStart` mode named by
    /// `startExpr`, for the no-capture and capture-bearing call shapes.
    ///
    /// `builderCallee` picks the family: `launch` returns a `Job` handle,
    /// `async` a `Deferred` one carrying the block's result, so the two cannot
    /// share entry points even where their scheduling is identical.
    ///
    /// A start argument that is not a compile-time-known entry (a
    /// `CoroutineStart` read out of a variable, say) falls back to DEFAULT:
    /// that is Kotlin's own default, and the only mode whose scheduling can be
    /// chosen without knowing the value.
    ///
    /// Each name is spelled out rather than assembled from a base and a suffix
    /// so that every emitted `kk_*` symbol stays greppable (and so reachable by
    /// `Scripts/validate_runtime_abi_links.sh`).
    private func coroutineStartRuntimeCallees(
        startExpr: KIRExprID,
        builderCallee: InternedString,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> (zeroArg: InternedString, withCont: InternedString) {
        let interner = rewrite.ctx.interner
        let startMode = coroutineStartEntryName(
            startExpr,
            symbolByExprRaw: symbolByExprRaw,
            using: rewrite
        )
        if builderCallee == interner.intern("async") {
            switch startMode {
            case "LAZY":
                return (
                    interner.intern("kk_kxmini_async_lazy"),
                    interner.intern("kk_kxmini_async_lazy_with_cont")
                )
            case "UNDISPATCHED":
                return (
                    interner.intern("kk_kxmini_async_undispatched"),
                    interner.intern("kk_kxmini_async_undispatched_with_cont")
                )
            default:
                // DEFAULT, ATOMIC, and anything unresolved: schedule immediately.
                return (
                    interner.intern("kk_kxmini_async"),
                    interner.intern("kk_kxmini_async_with_cont")
                )
            }
        }
        switch startMode {
        case "LAZY":
            return (
                interner.intern("kk_kxmini_launch_lazy"),
                interner.intern("kk_kxmini_launch_lazy_with_cont")
            )
        case "UNDISPATCHED":
            return (
                interner.intern("kk_kxmini_launch_undispatched"),
                interner.intern("kk_kxmini_launch_undispatched_with_cont")
            )
        default:
            // DEFAULT, ATOMIC, and anything unresolved: schedule immediately.
            return (
                interner.intern("kk_kxmini_launch"),
                interner.intern("kk_kxmini_launch_with_cont")
            )
        }
    }

    /// The `CoroutineStart` entry name a start argument refers to, when it is a
    /// compile-time-known entry. The owner check keeps a same-named entry of
    /// some other enum from being read as a `CoroutineStart` one.
    func coroutineStartEntryName(
        _ exprID: KIRExprID,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> String? {
        guard let sema = rewrite.ctx.sema,
              let symbol = symbolReference(
                  for: exprID,
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let info = sema.symbols.symbol(symbol),
              info.fqName.count >= 2
        else {
            return nil
        }
        let interner = rewrite.ctx.interner
        guard interner.resolve(info.fqName[info.fqName.count - 2]) == "CoroutineStart" else {
            return nil
        }
        return interner.resolve(info.name)
    }

    // Receiver-aware rewrite for `CoroutineScope.launch { block }`. Mirrors the
    // dispatcher-aware launch rewrite above: the receiver (like the dispatcher) is
    // an extra argument in front of the suspend function reference rather than a
    // capture threaded through the continuation, since it identifies *where* to
    // launch rather than data the launched body closes over.
    func rewriteCoroutineScopeLaunchCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.arguments.count >= 2 else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0001",
                "CoroutineScope.launch expects a receiver and a suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }
        let scopeExpr = call.arguments[0]
        let suspendArgExpr = call.arguments[1]

        guard let suspendSymbol = symbolReference(
                  for: suspendArgExpr,
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[suspendSymbol]
        else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0002",
                "CoroutineScope.launch requires a suspend function reference argument.",
                range: nil
            )
            return [call.instruction]
        }

        // Captured outer variables of the launched lambda are appended after the
        // suspend function reference (see the kk_coroutine_scope_launch capture
        // injection in CallLowerer). Non-capturing blocks take the simple
        // functionID path; capturing blocks thread their captures through a
        // continuation like the dispatcher-aware launch does.
        let targetArity = rewrite.suspendFunctionArityBySymbol[suspendSymbol] ?? 0
        let extraArgs = Array(call.arguments.dropFirst(2))
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0003",
                "Coroutine launcher 'launch' passed \(extraArgs.count) capture argument(s) but referenced suspend function expects \(targetArity).",
                range: nil
            )
            return [call.instruction]
        }

        if targetArity == 0 {
            return rewriteZeroArgCoroutineScopeLauncherCall(
                scopeExpr: scopeExpr,
                loweredTarget: loweredTarget,
                call: call,
                using: rewrite
            )
        }

        guard let thunk = rewrite.launcherThunkByOriginalSymbol[suspendSymbol] else {
            assertionFailure("Internal compiler error: launcher thunk missing for capturing CoroutineScope.launch")
            return [call.instruction]
        }
        return rewriteArgBearingCoroutineScopeLauncherCall(
            scopeExpr: scopeExpr,
            loweredTarget: loweredTarget,
            thunk: thunk,
            extraArgs: extraArgs,
            call: call,
            using: rewrite
        )
    }

    // Receiver-aware counterpart to rewriteArgBearingDispatcherLauncherCall: threads
    // the launched lambda's captured outer variables through a fresh continuation and
    // routes to kk_coroutine_scope_launch_with_cont, keeping the explicit receiver
    // scope in front of the thunk reference (BUG-049).
    func rewriteArgBearingCoroutineScopeLauncherCall(
        scopeExpr: KIRExprID,
        loweredTarget: LoweredSuspendFunction,
        thunk: LoweredSuspendFunction,
        extraArgs: [KIRExprID],
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let runtimeCallee = rewrite.ctx.interner.intern("kk_coroutine_scope_launch_with_cont")

        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        let thunkRefExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(
            .call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [scopeExpr, thunkRefExpr, continuationExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            )
        )
        return rewritten
    }

    func rewriteZeroArgCoroutineScopeLauncherCall(
        scopeExpr: KIRExprID,
        loweredTarget: LoweredSuspendFunction,
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let entryFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )

        return [
            .constValue(result: entryPointExpr, value: .symbolRef(loweredTarget.symbol)),
            .constValue(result: entryFunctionID, value: .intLiteral(Int64(loweredTarget.symbol.rawValue))),
            .call(
                symbol: nil,
                callee: rewrite.coroutineScopeLaunchCallee,
                arguments: [scopeExpr, entryPointExpr, entryFunctionID],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            ),
        ]
    }

    func rewriteZeroArgLauncherCall(
        runtimeLauncherCallee: InternedString,
        loweredTarget: LoweredSuspendFunction,
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let structuredBlockingRuntimes: Set<InternedString> = [
            rewrite.ctx.interner.intern("kk_kxmini_run_blocking"),
        ]
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let entryFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )

        return [
            .constValue(result: entryPointExpr, value: .symbolRef(loweredTarget.symbol)),
            .constValue(result: entryFunctionID, value: .intLiteral(Int64(loweredTarget.symbol.rawValue))),
            .call(
                symbol: nil,
                callee: runtimeLauncherCallee,
                arguments: [entryPointExpr, entryFunctionID],
                result: call.result,
                canThrow: call.canThrow || structuredBlockingRuntimes.contains(runtimeLauncherCallee),
                thrownResult: call.thrownResult
            ),
        ]
    }

    func rewriteArgBearingLauncherCall(
        runtimeWithContCallee: InternedString,
        loweredTarget: LoweredSuspendFunction,
        thunk: LoweredSuspendFunction,
        extraArgs: [KIRExprID],
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let structuredBlockingRuntimes: Set<InternedString> = [
            rewrite.ctx.interner.intern("kk_kxmini_run_blocking_with_cont"),
        ]
        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )

        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        let thunkRefExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(
            .call(
                symbol: nil,
                callee: runtimeWithContCallee,
                arguments: [thunkRefExpr, continuationExpr],
                result: call.result,
                canThrow: call.canThrow || structuredBlockingRuntimes.contains(runtimeWithContCallee),
                thrownResult: nil
            )
        )
        return rewritten
    }

    func rewriteProduceLauncherCall(
        runtimeWithContCallee: InternedString,
        loweredTarget: LoweredSuspendFunction,
        thunk: LoweredSuspendFunction,
        extraArgs: [KIRExprID],
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )

        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        // Slot 0 is reserved for the produced channel receiver.
        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index + 1)),
                type: rewrite.intType
            )
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        let thunkRefExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(
            .call(
                symbol: nil,
                callee: runtimeWithContCallee,
                arguments: [thunkRefExpr, continuationExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            )
        )
        return rewritten
    }

    /// KSP-1573: rewrite `__kk_produce_launch(channel, block)` — the runtime
    /// bridge the bundled produce/actor bodies emit — into the launcher
    /// continuation convention. The channel arrives as call.arguments[0]
    /// (already created by the bundled `Channel(capacity)` factory, so its
    /// capacity/overflow policy is honored), the suspend block as
    /// call.arguments[1]; the produced coroutine's receiver (`this`
    /// ProducerScope/ActorScope) is bound at launcherArgs[0] by the runtime
    /// and captures occupy slots 1...
    ///
    /// Only a block that was a lambda *literal* marked
    /// coroutine-launcher gets that convention: it is the sole case where
    /// LambdaLowerer emits the receiver-first `(receiver, cap0..capN)`
    /// suspend-function layout. A suspend function *value* (a block stored
    /// in a variable, a callable reference, a local suspend function)
    /// keeps the ordinary `(cap0..capN, receiver)` layout even though it
    /// still resolves to a suspend symbol here — launcherArgs[0]=channel
    /// would land in its leading capture slot. Leave such calls in place
    /// for `__kk_produce_launch` to invoke under the boxed (fnPtr, env)
    /// function-value convention.
    func rewriteChannelProduceLaunchCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.arguments.count >= 2 else {
            return nil
        }
        let channelExpr = call.arguments[0]
        let suspendArgExpr = call.arguments[1]
        guard let suspendSymbol = symbolReference(
                  for: suspendArgExpr,
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[suspendSymbol],
              let thunk = rewrite.launcherThunkByOriginalSymbol[suspendSymbol]
        else {
            return rewriteProduceLaunchFunctionValueCall(
                call: call,
                channelExpr: channelExpr,
                suspendArgExpr: suspendArgExpr,
                using: rewrite
            )
        }

        guard isCoroutineLauncherMarkedBlock(suspendSymbol, using: rewrite) else {
            return rewriteProduceLaunchFunctionValueCall(
                call: call,
                channelExpr: channelExpr,
                suspendArgExpr: suspendArgExpr,
                using: rewrite
            )
        }

        // The trailing argument may be the function-value environment, not
        // flattened captures. Prefer the lambda reference's capture metadata.
        let trailingCaptures = Array(call.arguments.dropFirst(2))
        let captures = rewrite.module.arena.callableValueInfo(for: suspendArgExpr)?.captureArguments
            ?? rewrite.module.arena.lambdaCaptureArgsBySymbol[suspendSymbol]
            ?? trailingCaptures

        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )

        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        // Slot 0 is reserved for the produced channel receiver.
        for (index, argExpr) in captures.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index + 1)),
                type: rewrite.intType
            )
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        let thunkRefExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(
            .call(
                symbol: nil,
                callee: rewrite.ctx.interner.intern("__kk_produce_launch_with_cont"),
                arguments: [channelExpr, thunkRefExpr, continuationExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            )
        )
        return rewritten
    }

    /// KSP-1583: rewrite `kk_test_run_blocking(context, timeout, block)` —
    /// the extern `kotlinx.coroutines.test.runTest` — into the launcher
    /// continuation convention. The suspend block is the trailing argument;
    /// the runtime mints the `TestScope` (a real RuntimeCoroutineScope over
    /// the given context) and binds it at launcherArgs[0] in
    /// `kk_test_run_blocking_with_cont`, so captures occupy slots 1...
    /// When the block doesn't resolve to a suspend symbol (a block stored
    /// in a variable or forwarded from another call), the raw call is left
    /// in place for `kk_test_run_blocking` to invoke through the boxed
    /// suspend-value convention (env-first thunk, mirroring
    /// `kk_function_invoke`'s box dispatch).
    func rewriteTestScopeRunBlockingCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        // `runTest(context, timeout, testBody)` — the block is always
        // arguments[2]; flattened captures (when the emitter produces them)
        // trail after it, same as `__kk_produce_launch`.
        guard call.arguments.count >= 3 else {
            return nil
        }
        let contextExpr = call.arguments[0]
        let suspendArgExpr = call.arguments[2]
        guard let suspendSymbol = symbolReference(
                  for: suspendArgExpr,
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[suspendSymbol],
              let thunk = rewrite.launcherThunkByOriginalSymbol[suspendSymbol]
        else {
            return nil
        }

        // Captures either arrive flattened as trailing call args or ride
        // inside the suspend value's callable info — use whichever form the
        // emitter produced.
        let trailingCaptures = Array(call.arguments.dropFirst(3))
        let captures: [KIRExprID] = trailingCaptures.isEmpty
            ? (rewrite.module.arena.callableValueInfo(for: suspendArgExpr)?.captureArguments ?? [])
            : trailingCaptures

        // The suspend thunk's launcherArgs mirror the lowered function's
        // parameter layout. Launcher-marked literals lower receiver-first
        // (`[receiver, cap0..capN]`), so the scope lands in slot 0 and
        // captures in slots 1... Unmarked suspend values (a block held in a
        // variable — `val body = { ... }; runTest(testBody = body)`) lower
        // captures-first (`[cap0..capN, receiver]`), so the scope lands in
        // the LAST slot and captures in slots 0..N-1. A variable-held
        // value's env is not recoverable at the call site (KUU-1016), so
        // unavailable capture slots are seeded 0 — the degraded "captures
        // arrive null" behaviour documented for boxed suspend values.
        let receiverFirst = rewrite.module.arena.receiverFirstLauncherLambdaSymbols
            .contains(suspendSymbol)
        let suspendParamCount = rewrite.module.arena.function(for: suspendSymbol)?.params.count
            ?? (captures.count + 1)
        let scopeSlot = receiverFirst ? 0 : suspendParamCount - 1
        guard scopeSlot >= 0 else {
            return nil
        }

        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let zeroExpr = rewrite.module.arena.appendExpr(
            .intLiteral(0),
            type: rewrite.intType
        )

        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        func appendLauncherArgSet(_ slot: Int, _ value: KIRExprID) {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(slot)),
                type: rewrite.intType
            )
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, value],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        if receiverFirst {
            for (index, argExpr) in captures.enumerated() {
                appendLauncherArgSet(index + 1, argExpr)
            }
        } else {
            for index in 0..<scopeSlot {
                appendLauncherArgSet(index, index < captures.count ? captures[index] : zeroExpr)
            }
        }
        // Reserve the scope slot so launcherArgs is sized for it; the
        // runtime overwrites it with the minted scope handle.
        appendLauncherArgSet(scopeSlot, zeroExpr)

        let thunkRefExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let scopeSlotExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(scopeSlot)),
            type: rewrite.intType
        )
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(thunk.symbol)))
        rewritten.append(
            .call(
                symbol: nil,
                callee: rewrite.ctx.interner.intern("kk_test_run_blocking_with_cont"),
                arguments: [contextExpr, thunkRefExpr, continuationExpr, scopeSlotExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            )
        )
        return rewritten
    }

    /// Rewrites `__kk_produce_launch(channel, blockValue)` — a produce/actor
    /// block that arrived as a suspend function *value* — into the boxed
    /// (fnPtr, env) convention `__kk_produce_launch` invokes at runtime:
    /// `(cap0..capN, receiver, outThrown)` with captures first.
    ///
    /// The value's env slot is materialized here because the value itself
    /// crosses `block` as a bare fnPtr: its captures live only in the
    /// callable info registered for the argument expression. With callable
    /// info, env packs the captures exactly like
    /// `CallLowerer.splitCallableLambdaArgument` (0 → `0`, one → the raw
    /// capture, several → a `kk_object_new(2+N, classID: 0)` box). Without
    /// it the runtime resolves the opaque value, preserving the closure
    /// parameter of a boxed function even when its environment is zero.
    func rewriteProduceLaunchFunctionValueCall(
        call: CallRewriteInput,
        channelExpr: KIRExprID,
        suspendArgExpr: KIRExprID,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction] {
        let arena = rewrite.module.arena
        var instructions: [KIRInstruction] = []

        // Imported calls may already carry the raw entry point and environment.
        // Reconstructing them from the entry point would discard their captures.
        if call.arguments.count == 3 {
            return [.call(
                symbol: call.symbol,
                callee: call.callee,
                arguments: call.arguments,
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult,
                isSuperCall: call.isSuperCall
            )]
        }

        let entryExpr: KIRExprID
        let envExpr: KIRExprID
        if let callableInfo = arena.callableValueInfo(for: suspendArgExpr) {
            entryExpr = arena.appendExpr(.symbolRef(callableInfo.symbol), type: rewrite.intType)
            instructions.append(.constValue(result: entryExpr, value: .symbolRef(callableInfo.symbol)))
            if callableInfo.hasClosureParam {
                let closureExpr: KIRExprID
                if callableInfo.captureArguments.count >= 2 {
                    closureExpr = emitPackedCaptureEnvironment(
                        callableInfo.captureArguments, using: rewrite, into: &instructions
                    )
                } else if let capture = callableInfo.captureArguments.first {
                    closureExpr = capture
                } else {
                    closureExpr = arena.appendExpr(.intLiteral(0), type: rewrite.intType)
                    instructions.append(.constValue(result: closureExpr, value: .intLiteral(0)))
                }
                // Keep the closure slot, including zero or a packed capture object,
                // intact rather than expanding it into the adapter's parameters.
                envExpr = emitPackedCaptureEnvironment([closureExpr], using: rewrite, into: &instructions)
            } else {
                switch callableInfo.captureArguments.count {
                case 0:
                    envExpr = arena.appendExpr(.intLiteral(0), type: rewrite.intType)
                    instructions.append(.constValue(result: envExpr, value: .intLiteral(0)))
                case 1:
                    envExpr = callableInfo.captureArguments[0]
                default:
                    envExpr = emitPackedCaptureEnvironment(
                        callableInfo.captureArguments,
                        using: rewrite,
                        into: &instructions
                    )
                }
            }
        } else {
            // The runtime must distinguish a boxed closure from a raw entry point
            // before deciding whether its environment can be expanded.
            entryExpr = suspendArgExpr
            envExpr = arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            instructions.append(.constValue(result: envExpr, value: .intLiteral(0)))
        }

        instructions.append(
            .call(
                symbol: call.symbol,
                callee: call.callee,
                arguments: [channelExpr, entryExpr, envExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult,
                isSuperCall: call.isSuperCall
            )
        )
        return instructions
    }

    /// Emits `kk_object_new(2+N, classID: 0)` with `captures` stored at
    /// slots 2... — the packed-environment shape
    /// `CallLowerer.splitCallableLambdaArgument` produces and
    /// `__kk_produce_launch` expands.
    private func emitPackedCaptureEnvironment(
        _ captures: [KIRExprID],
        using rewrite: SuspendRewriteContext,
        into instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let arena = rewrite.module.arena
        let interner = rewrite.ctx.interner
        let slotCountExpr = arena.appendExpr(
            .intLiteral(Int64(2 + captures.count)),
            type: rewrite.intType
        )
        instructions.append(.constValue(
            result: slotCountExpr,
            value: .intLiteral(Int64(2 + captures.count))
        ))
        let classIDExpr = arena.appendExpr(.intLiteral(0), type: rewrite.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        let envExpr = arena.appendTemporary(type: rewrite.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: envExpr,
            canThrow: false,
            thrownResult: nil
        ))
        for (index, captureExpr) in captures.enumerated() {
            let offsetExpr = arena.appendExpr(
                .intLiteral(Int64(index + 2)),
                type: rewrite.intType
            )
            instructions.append(.constValue(
                result: offsetExpr,
                value: .intLiteral(Int64(index + 2))
            ))
            let storeResult = arena.appendTemporary(type: rewrite.intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [envExpr, offsetExpr, captureExpr],
                result: storeResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
        return envExpr
    }
}
