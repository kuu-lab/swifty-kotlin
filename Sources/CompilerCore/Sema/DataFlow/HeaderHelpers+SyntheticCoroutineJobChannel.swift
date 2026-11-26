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

        let jobMembers = coroutineMemberRows(of: jobSymbol, type: jobType, symbols: symbols, interner: interner)
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("start"), arity: 0) {
            jobMembers.fn("start", "kk_job_start", ret: types.booleanType)
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("cancel"), arity: 0) {
            jobMembers.fn("cancel", "kk_job_cancel", ret: types.unitType)
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("cancel"), arity: 1) {
            jobMembers.fn("cancel", "kk_job_cancel_with_cause", [(name: "cause", type: types.nullableAnyType)], ret: types.unitType)
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("join"), arity: 0) {
            jobMembers.fn("join", "kk_job_join", ret: types.unitType)
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("awaitCompletion"), arity: 0) {
            jobMembers.fn("awaitCompletion", "kk_job_await_completion", ret: types.unitType)
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("complete"), arity: 0) {
            jobMembers.fn("complete", "kk_job_complete", [(name: "value", type: types.anyType)], ret: types.booleanType)
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("Job")], name: interner.intern("completeExceptionally"), arity: 1) {
            jobMembers.fn("completeExceptionally", "kk_job_complete_exceptionally", [(name: "exception", type: types.nullableAnyType)], ret: types.booleanType)
        }

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
        let coroutineScopeMembers = coroutineMemberRows(of: coroutineScopeSymbol, type: coroutineScopeType, symbols: symbols, interner: interner)
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("CoroutineScope")], name: interner.intern("launch"), arity: 3) {
            coroutineScopeMembers.fn(
                "launch",
                "kk_coroutine_scope_launch",
                [(name: "block", type: types.make(.functionType(FunctionType(receiver: coroutineScopeType, params: [], returnType: types.unitType, isSuspend: true, nullability: .nonNull))))],
                ret: jobType
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("CoroutineScope")], name: interner.intern("cancel"), arity: 1) {
            coroutineScopeMembers.fn("cancel", "kk_coroutine_scope_cancel", ret: types.unitType)
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
            let deferredMembers = coroutineMemberRows(of: deferredSymbol, type: deferredType, symbols: symbols, interner: interner)
            deferredMembers.fn("await", "kk_kxmini_async_await", ret: types.anyType)
        }
        let channelMembers = coroutineMemberRows(of: channelSymbol, type: channelType, symbols: symbols, interner: interner)
        let channelElementType = types.nominalTypeParameterSymbols(for: channelSymbol).first.map {
            types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull)))
        } ?? types.anyType
        channelMembers.fn(
            "receive",
            "kk_channel_receive",
            ret: channelElementType,
            typeParameterSymbols: types.nominalTypeParameterSymbols(for: channelSymbol),
            classTypeParameterCount: types.nominalTypeParameterSymbols(for: channelSymbol).count,
            isSuspend: true
        )
    }
}
