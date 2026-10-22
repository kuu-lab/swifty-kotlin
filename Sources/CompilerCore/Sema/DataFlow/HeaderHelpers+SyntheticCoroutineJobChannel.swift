extension DataFlowSemaPhase {
    func registerCoroutineJobChannelStubs(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let channelsPkg = context.channelsPkg
        let channelSymbol = context.channelSymbol!
        let channelType = context.channelType!
        let coroutinesPkg = context.coroutinesPkg
        let jobSymbol = context.jobSymbol!
        let jobType = context.jobType!
        let coroutineContextType = context.coroutineContextType!
        let coroutineScopeSymbol = context.coroutineScopeSymbol!
        let coroutineScopeType = context.coroutineScopeType!
        let deferredSymbol = context.deferredSymbol!
        let deferredType = context.deferredType!

        // KSP-678: the `Channel()` / `Channel(capacity)` factories are now
        // provided by bundled Kotlin source
        // (Sources/CompilerCore/Stdlib/kotlin/coroutines/channels/Channels.kt),
        // which bridges to the residual kk_channel_create runtime entry point via
        // @KsSymbolName. No synthetic constructor or factory bridges are
        // registered here.

        // STDLIB-CORO-078: `ReceiveChannel<T>` is the read-only view of `Channel<T>`
        // that `produce { }` returns in real kotlinx.coroutines. Registered as a
        // type alias (rather than a separate interface) so send/receive/close/
        // isClosedForReceive/for-loop iteration resolve through the same Channel
        // member lookup instead of duplicating it for a second symbol.
        let receiveChannelName = interner.intern("ReceiveChannel")
        let receiveChannelFQName = channelsPkg + [receiveChannelName]
        if symbols.lookup(fqName: receiveChannelFQName) == nil {
            let receiveChannelAliasSymbol = symbols.define(
                kind: .typeAlias,
                name: receiveChannelName,
                fqName: receiveChannelFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            let receiveChannelTypeParamName = interner.intern("T")
            let receiveChannelTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: receiveChannelTypeParamName,
                fqName: receiveChannelFQName + [receiveChannelTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setTypeAliasTypeParameters([receiveChannelTypeParamSymbol], for: receiveChannelAliasSymbol)
            let receiveChannelTypeParamType = types.make(.typeParam(TypeParamType(
                symbol: receiveChannelTypeParamSymbol,
                nullability: .nonNull
            )))
            let receiveChannelUnderlyingType = types.make(.classType(ClassType(
                classSymbol: channelSymbol,
                args: [.invariant(receiveChannelTypeParamType)],
                nullability: .nonNull
            )))
            symbols.setTypeAliasUnderlyingType(receiveChannelUnderlyingType, for: receiveChannelAliasSymbol)
        }

        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("start"), arity: 0) {
            registerSyntheticCoroutineMember(
                ownerSymbol: jobSymbol,
                ownerType: jobType,
                name: "start",
                externalLinkName: "kk_job_start",
                returnType: types.booleanType,
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("cancel"), arity: 0) {
            registerSyntheticCoroutineMember(
                ownerSymbol: jobSymbol,
                ownerType: jobType,
                name: "cancel",
                externalLinkName: "kk_job_cancel",
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("cancel"), arity: 1) {
            registerSyntheticCoroutineMember(
                ownerSymbol: jobSymbol,
                ownerType: jobType,
                name: "cancel",
                externalLinkName: "kk_job_cancel_with_cause",
                returnType: types.unitType,
                parameters: [(name: "cause", type: types.nullableAnyType)],
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("join"), arity: 0) {
            registerSyntheticCoroutineMember(
                ownerSymbol: jobSymbol,
                ownerType: jobType,
                name: "join",
                externalLinkName: "kk_job_join",
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("awaitCompletion"), arity: 0) {
            registerSyntheticCoroutineMember(
                ownerSymbol: jobSymbol,
                ownerType: jobType,
                name: "awaitCompletion",
                externalLinkName: "kk_job_await_completion",
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("complete"), arity: 0) {
            registerSyntheticCoroutineMember(
                ownerSymbol: jobSymbol,
                ownerType: jobType,
                name: "complete",
                externalLinkName: "kk_job_complete",
                returnType: types.booleanType,
                parameters: [(name: "value", type: types.anyType)],
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("completeExceptionally"), arity: 1) {
            registerSyntheticCoroutineMember(
                ownerSymbol: jobSymbol,
                ownerType: jobType,
                name: "completeExceptionally",
                externalLinkName: "kk_job_complete_exceptionally",
                returnType: types.booleanType,
                parameters: [(name: "exception", type: types.nullableAnyType)],
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-CORO-BUG-04: bare `isActive` reference (no explicit
        // CoroutineScope receiver) inside a coroutine builder body, e.g.
        // `launch { if (isActive) { ... } }`.
        registerSyntheticCoroutineTopLevelProperty(
            named: "isActive",
            packageFQName: coroutinesPkg,
            returnType: types.booleanType,
            externalLinkName: "kk_coroutine_current_is_active",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "isActive",
            propertyType: types.booleanType,
            externalLinkName: "kk_job_is_active",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "isCompleted",
            propertyType: types.booleanType,
            externalLinkName: "kk_job_is_completed",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "isCancelled",
            propertyType: types.booleanType,
            externalLinkName: "kk_job_is_cancelled",
            symbols: symbols,
            interner: interner
        )

        let completableJobType = (bundledIndex.containsNominal(fqName: coroutinesPkg + [interner.intern("CompletableJob")])
            || symbols.lookup(fqName: coroutinesPkg + [interner.intern("CompletableJob")]) != nil)
            ? types.make(.classType(ClassType(
                classSymbol: ensureInterfaceSymbol(named: "CompletableJob", in: coroutinesPkg, symbols: symbols, interner: interner),
                args: [], nullability: .nonNull
            ))) : jobType
        if !bundledIndex.contains(ownerFQName: coroutinesPkg, name: interner.intern("Job"), arity: 1) {
            registerSyntheticCoroutineTopLevelFunction(
                named: "Job",
                packageFQName: coroutinesPkg,
                parameters: [],
                returnType: completableJobType,
                externalLinkName: "kk_job_new",
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg, name: interner.intern("SupervisorJob"), arity: 1) {
            registerSyntheticCoroutineTopLevelFunction(
                named: "SupervisorJob",
                packageFQName: coroutinesPkg,
                parameters: [],
                returnType: completableJobType,
                externalLinkName: "kk_supervisor_job_new",
                symbols: symbols,
                interner: interner
            )
        }

        symbols.setPropertyType(coroutineScopeType, for: coroutineScopeSymbol)
        if !bundledIndex.contains(ownerFQName: coroutinesPkg, name: interner.intern("CoroutineScope"), arity: 1) {
            registerSyntheticCoroutineTopLevelFunction(
                named: "CoroutineScope",
                packageFQName: coroutinesPkg,
                parameters: [(name: "context", type: coroutineContextType)],
                returnType: coroutineScopeType,
                externalLinkName: "kk_coroutine_scope_new_with_context",
                symbols: symbols,
                interner: interner
            )
        }
        // `CoroutineScope.launch { block }`: a receiver-bearing member call. The general
        // member-call emission path (appendReceiverToMemberArguments in
        // CallLowerer+MemberCallEmission.swift) already prepends the receiver as
        // arguments[0] whenever the chosen callee's FunctionSignature.receiverType is
        // set, so this call reaches CoroutineLoweringPass as a 2-argument call
        // [receiverExpr, blockRef] -- the same shape as the dispatcher-aware top-level
        // `launch(dispatcher) { }`. CoroutineLoweringPass+LauncherSupport.swift's
        // rewriteLauncherCall special-cases this externalLinkName up front and routes
        // it through rewriteCoroutineScopeLaunchCall, which threads the receiver through
        // to a dedicated `kk_coroutine_scope_launch(scopeHandle, entryPointRaw,
        // functionID)` runtime entry point.
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("CoroutineScope")], name: interner.intern("launch"), arity: 3) {
            registerSyntheticCoroutineMember(
                ownerSymbol: coroutineScopeSymbol,
                ownerType: coroutineScopeType,
                name: "launch",
                externalLinkName: "kk_coroutine_scope_launch",
                returnType: jobType,
                parameters: [(
                    name: "block",
                    type: types.make(.functionType(FunctionType(
                        receiver: coroutineScopeType,
                        params: [],
                        returnType: types.unitType,
                        isSuspend: true,
                        nullability: .nonNull
                    )))
                )],
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("CoroutineScope")], name: interner.intern("cancel"), arity: 1) {
            registerSyntheticCoroutineMember(
                ownerSymbol: coroutineScopeSymbol,
                ownerType: coroutineScopeType,
                name: "cancel",
                externalLinkName: "kk_coroutine_scope_cancel",
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("CoroutineScope")], name: interner.intern("isActive"), arity: 0) {
            registerSyntheticObjectProperty(
                ownerSymbol: coroutineScopeSymbol,
                ownerType: coroutineScopeType,
                name: "isActive",
                propertyType: types.booleanType,
                externalLinkName: "kk_coroutine_scope_is_active",
                symbols: symbols,
                interner: interner
            )
        }
        if !symbols.isSourceBackedSymbol(deferredSymbol) {
            registerSyntheticCoroutineMember(
                ownerSymbol: deferredSymbol,
                ownerType: deferredType,
                name: "await",
                externalLinkName: "kk_kxmini_async_await",
                returnType: types.anyType,
                symbols: symbols,
                interner: interner
            )
        }
        // KSP-676: StateFlow / MutableStateFlow and Flow.stateIn are bundled
        // Kotlin source (StateFlow.kt), so no synthetic constructor or member
        // stubs are registered here.
        registerSyntheticCoroutineMember(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "send",
            externalLinkName: "kk_channel_send",
            returnType: types.unitType,
            parameters: [(name: "value", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "receive",
            externalLinkName: "kk_channel_receive",
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        // KSP-678: Channel.close / isClosedForSend / isClosedForReceive are now
        // provided by bundled Kotlin source
        // (Sources/CompilerCore/Stdlib/kotlin/coroutines/channels/Channels.kt),
        // which bridges to the residual kk_channel_close /
        // kk_channel_is_closed_for_send / kk_channel_is_closed_for_receive
        // runtime entry points via @KsSymbolName. No synthetic stubs are
        // registered for them here.
    }
}
