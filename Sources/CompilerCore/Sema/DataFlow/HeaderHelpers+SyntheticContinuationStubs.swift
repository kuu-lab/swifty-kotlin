extension DataFlowSemaPhase {
    func registerContinuationStubs(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let kotlinCoroutinesPkg = context.kotlinCoroutinesPkg
        let coroutinesPkg = context.coroutinesPkg
        let kotlinResultSymbol = context.kotlinResultSymbol!
        let continuationFactoryTType = context.continuationFactoryTType!
        let continuationFactoryTypeParamSymbol = context.continuationFactoryTypeParamSymbol!
        let continuationSymbol = context.continuationSymbol!
        let continuationTypeParameterSymbol = context.continuationTypeParameterSymbol!
        let continuationTType = context.continuationTType!
        let continuationType = context.continuationType!
        let kotlinCoroutineContextType = context.kotlinCoroutineContextType!
        let exceptionType = context.exceptionType!
        let rootCancellationSymbol = context.rootCancellationSymbol!
        let jobSymbol = context.jobSymbol!
        let jobType = context.jobType!
        let deferredSymbol = context.deferredSymbol!
        let deferredType = context.deferredType!
        let flowInterfaceSymbol = context.flowInterfaceSymbol!
        let flowRawType = context.flowRawType!
        let dispatcherSymbol = context.dispatcherSymbol!
        let dispatcherType = context.dispatcherType!
        let coroutineStartSymbol = context.coroutineStartSymbol!
        let coroutineStartType = context.coroutineStartType!
        let channelSymbol = context.channelSymbol!
        let channelType = context.channelType!
        let channelIteratorSymbol = context.channelIteratorSymbol!
        let channelIteratorType = context.channelIteratorType!
        let continuationInterceptorSymbol = context.continuationInterceptorSymbol!
        let continuationInterceptorType = context.continuationInterceptorType!
        let cancellationSymbol = context.cancellationSymbol!
        let cancellationType = context.cancellationType!
        let cancellationIsSourceBacked = context.cancellationIsSourceBacked
        let illegalStateExceptionSymbol = context.illegalStateExceptionSymbol
        let exceptionSymbol = context.exceptionSymbol!

        let resultOfContinuationFactoryTType = types.make(.classType(ClassType(
            classSymbol: kotlinResultSymbol,
            args: [.invariant(continuationFactoryTType)],
            nullability: .nonNull
        )))
        let continuationFactoryResumeWithType = types.make(.functionType(FunctionType(
            params: [resultOfContinuationFactoryTType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let continuationFactoryReturnType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(continuationFactoryTType)],
            nullability: .nonNull
        )))
        registerSyntheticCoroutineTopLevelFunction(
            named: "Continuation",
            packageFQName: kotlinCoroutinesPkg,
            parameters: [
                (name: "context", type: kotlinCoroutineContextType),
                (name: "resumeWith", type: continuationFactoryResumeWithType),
            ],
            returnType: continuationFactoryReturnType,
            externalLinkName: "kk_coroutine_continuation_factory",
            explicitTypeParameterSymbols: [continuationFactoryTypeParamSymbol],
            valueParameterFQNameSuffixes: ["$factoryContext", "$factoryResumeWith"],
            symbols: symbols,
            interner: interner
        )

        if !bundledIndex.contains(
            ownerFQName: kotlinCoroutinesPkg + [interner.intern("Continuation")],
            name: interner.intern("context"),
            arity: 0
        ) {
            registerSyntheticObjectProperty(
                ownerSymbol: continuationSymbol,
                ownerType: continuationType,
                name: "context",
                propertyType: kotlinCoroutineContextType,
                externalLinkName: "kk_coroutine_continuation_context",
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticCoroutineTopLevelProperty(
            named: "coroutineContext",
            packageFQName: kotlinCoroutinesPkg,
            returnType: kotlinCoroutineContextType,
            externalLinkName: "kk_coroutine_current_context",
            symbols: symbols,
            interner: interner
        )
        if !bundledIndex.contains(ownerFQName: coroutinesPkg, name: interner.intern("currentCoroutineContext"), arity: 0) {
            // kotlinx.coroutines.currentCoroutineContext() is the suspend-function
            // equivalent of the kotlin.coroutines.coroutineContext property above;
            // both read the same ambient context, so they share a backing primitive.
            registerSyntheticCoroutineTopLevelFunction(
                named: "currentCoroutineContext",
                packageFQName: coroutinesPkg,
                parameters: [],
                returnType: kotlinCoroutineContextType,
                externalLinkName: "kk_coroutine_current_context",
                isSuspend: true,
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(
            ownerFQName: kotlinCoroutinesPkg + [interner.intern("Continuation")],
            name: interner.intern("resume"),
            arity: 1
        ) {
            registerSyntheticCoroutineExtensionFunction(
                named: "resume",
                packageFQName: kotlinCoroutinesPkg,
                receiverType: continuationType,
                externalLinkName: "kk_coroutine_continuation_resume",
                returnType: types.unitType,
                parameters: [(
                    name: "value",
                    type: continuationTType
                )],
                classTypeParameterCount: 1,
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(
            ownerFQName: kotlinCoroutinesPkg + [interner.intern("Continuation")],
            name: interner.intern("resumeWithException"),
            arity: 1
        ) {
            registerSyntheticCoroutineExtensionFunction(
                named: "resumeWithException",
                packageFQName: kotlinCoroutinesPkg,
                receiverType: continuationType,
                externalLinkName: "kk_coroutine_continuation_resume_with_exception",
                returnType: types.unitType,
                parameters: [(
                    name: "exception",
                    type: exceptionType
                )],
                classTypeParameterCount: 1,
                symbols: symbols,
                interner: interner
            )
        }

        let resultOfContinuationTType = types.make(.classType(ClassType(
            classSymbol: kotlinResultSymbol,
            args: [.invariant(continuationTType)],
            nullability: .nonNull
        )))
        if !bundledIndex.contains(
            ownerFQName: kotlinCoroutinesPkg + [interner.intern("Continuation")],
            name: interner.intern("resumeWith"),
            arity: 1
        ) {
            let continuationMembers = coroutineMemberRows(of: continuationSymbol, type: continuationType, symbols: symbols, interner: interner)
            continuationMembers.fn(
                "resumeWith", "kk_coroutine_continuation_resume_with", [(name: "result", type: resultOfContinuationTType)],
                ret: types.unitType, typeParameterSymbols: [continuationTypeParameterSymbol], classTypeParameterCount: 1
            )
        }
        let rootCancellationType = types.make(.classType(ClassType(
            classSymbol: rootCancellationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let coroutineSuspendedType = types.nullableAnyType

        symbols.setPropertyType(jobType, for: jobSymbol)
        symbols.setPropertyType(deferredType, for: deferredSymbol)
        symbols.setPropertyType(flowRawType, for: flowInterfaceSymbol)
        symbols.setPropertyType(dispatcherType, for: dispatcherSymbol)
        symbols.setPropertyType(coroutineStartType, for: coroutineStartSymbol)
        symbols.setPropertyType(channelType, for: channelSymbol)
        symbols.setPropertyType(channelIteratorType, for: channelIteratorSymbol)
        symbols.setPropertyType(cancellationType, for: cancellationSymbol)
        symbols.setPropertyType(continuationType, for: continuationSymbol)
        symbols.setPropertyType(continuationInterceptorType, for: continuationInterceptorSymbol)
        symbols.setPropertyType(rootCancellationType, for: rootCancellationSymbol)
        if !cancellationIsSourceBacked, let illegalStateExceptionSymbol {
            symbols.setDirectSupertypes([illegalStateExceptionSymbol], for: cancellationSymbol)
            types.setNominalDirectSupertypes([illegalStateExceptionSymbol], for: cancellationSymbol)
        }
        if !cancellationIsSourceBacked {
            symbols.setDirectSupertypes([exceptionSymbol], for: rootCancellationSymbol)
        }
        if !symbols.isSourceBackedSymbol(dispatcherSymbol) {
            symbols.setDirectSupertypes([continuationInterceptorSymbol], for: dispatcherSymbol)
        }
        types.setNominalTypeParameterSymbols([continuationTypeParameterSymbol], for: continuationSymbol)
        if !symbols.isSourceBackedSymbol(continuationSymbol) {
            types.setNominalTypeParameterVariances([.in], for: continuationSymbol)
        }

        context.rootCancellationType = rootCancellationType
        context.coroutineSuspendedType = coroutineSuspendedType
    }
}
