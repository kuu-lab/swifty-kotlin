extension DataFlowSemaPhase {
    func registerCoroutineLauncherStubs(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let coroutinesPkg = context.coroutinesPkg
        let coroutineScopeType = context.coroutineScopeType!
        let jobType = context.jobType!
        let dispatcherSymbol = context.dispatcherSymbol!
        let dispatcherType = context.dispatcherType!
        let coroutineStartType = context.coroutineStartType!
        let deferredType = context.deferredType!
        let continuationType = context.continuationType!
        let continuationTypeParameterSymbol = context.continuationTypeParameterSymbol!
        let channelsPkg = context.channelsPkg
        let channelSymbol = context.channelSymbol!
        let kotlinCoroutinesPkg = context.kotlinCoroutinesPkg

        if !bundledIndex.contains(ownerFQName: coroutinesPkg, name: interner.intern("runBlocking"), arity: 2) {
            registerSyntheticCoroutineTopLevelFunction(
                named: "runBlocking",
                packageFQName: coroutinesPkg,
                parameterName: "block",
                parameterType: types.make(.functionType(FunctionType(
                    receiver: coroutineScopeType,
                    params: [],
                    returnType: types.nullableAnyType,
                    isSuspend: true,
                    nullability: .nonNull
                ))),
                returnType: types.anyType,
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: coroutinesPkg + [interner.intern("CoroutineScope")], name: interner.intern("launch"), arity: 3) {
            registerSyntheticCoroutineTopLevelFunction(
                named: "launch",
                packageFQName: coroutinesPkg,
                parameterName: "block",
                parameterType: types.make(.functionType(FunctionType(
                    receiver: coroutineScopeType,
                    params: [],
                    returnType: types.unitType,
                    isSuspend: true,
                    nullability: .nonNull
                ))),
                returnType: jobType,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoroutineTopLevelFunction(
                named: "launch",
                packageFQName: coroutinesPkg,
                parameters: [
                    (name: "context", type: dispatcherType),
                    (name: "block", type: types.make(.functionType(FunctionType(
                        receiver: coroutineScopeType,
                        params: [],
                        returnType: types.unitType,
                        isSuspend: true,
                        nullability: .nonNull
                    )))),
                ],
                returnType: jobType,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticCoroutineTopLevelFunction(
                named: "launch",
                packageFQName: coroutinesPkg,
                parameters: [
                    (name: "start", type: coroutineStartType),
                    (name: "block", type: types.make(.functionType(FunctionType(
                        receiver: coroutineScopeType,
                        params: [],
                        returnType: types.unitType,
                        isSuspend: true,
                        nullability: .nonNull
                    )))),
                ],
                returnType: jobType,
                symbols: symbols,
                interner: interner
            )

        }

        let dispatcherMembers = coroutineMemberRows(of: dispatcherSymbol, type: dispatcherType, symbols: symbols, interner: interner)
        dispatcherMembers.fn(
            "interceptContinuation", "kk_continuation_interceptor_intercept_continuation", [(name: "continuation", type: continuationType)],
            ret: continuationType, typeParameterSymbols: [continuationTypeParameterSymbol]
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "async",
            packageFQName: coroutinesPkg,
            parameterName: "block",
            parameterType: types.make(.functionType(FunctionType(
                receiver: coroutineScopeType,
                params: [],
                returnType: types.nullableAnyType,
                isSuspend: true,
                nullability: .nonNull
            ))),
            returnType: deferredType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "async",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "start", type: coroutineStartType),
                (name: "block", type: types.make(.functionType(FunctionType(
                    receiver: coroutineScopeType,
                    params: [],
                    returnType: types.nullableAnyType,
                    isSuspend: true,
                    nullability: .nonNull
                )))),
            ],
            returnType: deferredType,
            symbols: symbols,
            interner: interner
        )
        // The `produce` block runs with a `Channel<T>` receiver so channel sends
        // resolve correctly.
        // KSP-1573: the bundled `CoroutineScope.produce` extension
        // (Stdlib/kotlinx/coroutines/channels/Produce.kt) supersedes this
        // stub; keep the synthetic only for configurations without that
        // source. The bundled index keys extensions on the receiver's owner
        // fqName, so the check keys off CoroutineScope.
        let coroutineScopeMemberOwner = coroutinesPkg + [interner.intern("CoroutineScope")]
        let functionName = interner.intern("produce")
        let hasSourceBackedProduce = bundledIndex.contains(
            ownerFQName: coroutineScopeMemberOwner,
            name: functionName,
            arity: 1
        ) || bundledIndex.contains(
            ownerFQName: coroutineScopeMemberOwner,
            name: functionName,
            arity: 2
        )
        let functionFQName = channelsPkg + [functionName]
        if !hasSourceBackedProduce, symbols.lookup(fqName: functionFQName) == nil {
            let typeParamName = interner.intern("T")
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let typeParamType = types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            let produceChannelType = types.make(.classType(ClassType(
                classSymbol: channelSymbol,
                args: [.invariant(typeParamType)],
                nullability: .nonNull
            )))
            let blockType = types.make(.functionType(FunctionType(
                receiver: produceChannelType,
                params: [],
                returnType: types.unitType,
                isSuspend: true,
                nullability: .nonNull
            )))
            let functionSymbol = symbols.define(
                kind: .function,
                name: functionName,
                fqName: functionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: channelsPkg) {
                symbols.setParentSymbol(packageSymbol, for: functionSymbol)
            }
            symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
            let paramName = interner.intern("block")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            symbols.setExternalLinkName("kk_produce", for: functionSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [blockType],
                    returnType: produceChannelType,
                    isSuspend: false,
                    valueParameterSymbols: [paramSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [typeParamSymbol]
                ),
                for: functionSymbol
            )
        }
        registerSyntheticCoroutineTopLevelFunction(
            named: "yield",
            packageFQName: coroutinesPkg,
            parameters: [],
            returnType: types.unitType,
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "awaitCancellation",
            packageFQName: coroutinesPkg,
            parameters: [],
            returnType: types.nothingType,
            externalLinkName: "kk_await_cancellation",
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "ensureActive",
            packageFQName: coroutinesPkg,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_ensure_active",
            symbols: symbols,
            interner: interner
        )
        guard !context.bundledIndex.contains(ownerFQName: coroutinesPkg, name: interner.intern("withContext"), arity: 2)
        else { return }
        let withContextContextSymbol = ensureInterfaceSymbol(
            named: "CoroutineContext",
            in: kotlinCoroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let withContextContextType = types.make(.classType(ClassType(
            classSymbol: withContextContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        let withContextFunctionFQName = coroutinesPkg + [interner.intern("withContext")]
        let withContextTypeParameterSymbol = ensureSyntheticTypeParameterSymbol(
            named: "T",
            in: withContextFunctionFQName + [interner.intern("$synthetic")],
            symbols: symbols,
            interner: interner
        )
        let withContextResultType = types.make(.typeParam(TypeParamType(
            symbol: withContextTypeParameterSymbol,
            nullability: .nonNull
        )))
        registerSyntheticCoroutineTopLevelFunction(
            named: "withContext",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "context", type: withContextContextType),
                (name: "block", type: types.make(.functionType(FunctionType(
                    receiver: coroutineScopeType,
                    params: [],
                    returnType: withContextResultType,
                    isSuspend: true,
                    nullability: .nonNull
                )))),
            ],
            returnType: withContextResultType,
            explicitTypeParameterSymbols: [withContextTypeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
    }

    func registerCoroutineBuilderStubs(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let flowPkg = context.flowPkg
        let flowBuilderLambdaType = context.flowBuilderLambdaType!
        let flowRawType = context.flowRawType!
        let coroutinesPkg = context.coroutinesPkg
        let kotlinCoroutineContextType = context.kotlinCoroutineContextType!
        let coroutineScopeType = context.coroutineScopeType!

        registerSyntheticCoroutineTopLevelFunction(
            named: "flow",
            packageFQName: flowPkg,
            parameters: [(name: "block", type: flowBuilderLambdaType)],
            returnType: flowRawType,
            externalLinkName: "kk_flow_create",
            syntheticTypeParameterNames: ["T"],
            symbols: symbols,
            interner: interner
        )

        guard !context.bundledIndex.contains(ownerFQName: coroutinesPkg, name: interner.intern("withContext"), arity: 2)
        else { return }
        let withContextFunctionFQName = coroutinesPkg + [interner.intern("withContext")]
        let withContextTypeParameterSymbol = ensureSyntheticTypeParameterSymbol(
            named: "T",
            in: withContextFunctionFQName + [interner.intern("$synthetic")],
            symbols: symbols,
            interner: interner
        )
        let withContextResultType = types.make(.typeParam(TypeParamType(
            symbol: withContextTypeParameterSymbol,
            nullability: .nonNull
        )))
        registerSyntheticCoroutineTopLevelFunction(
            named: "withContext",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "context", type: kotlinCoroutineContextType),
                (name: "block", type: types.make(.functionType(FunctionType(
                    receiver: coroutineScopeType,
                    params: [],
                    returnType: withContextResultType,
                    isSuspend: true,
                    nullability: .nonNull
                )))),
            ],
            returnType: withContextResultType,
            explicitTypeParameterSymbols: [withContextTypeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
    }
}
