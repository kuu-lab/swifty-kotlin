extension DataFlowSemaPhase {
    func registerFlowCollectMember(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let bundledIndex = context.bundledIndex
        let flowPkg = context.flowPkg
        let flowInterfaceSymbol = context.flowInterfaceSymbol!
        let flowTypeParamSymbol = context.flowTypeParamSymbol!
        let flowRawType = context.flowRawType!

        // Runtime-backed members are only needed without bundled Flow declarations.
        let flowElementType = types.make(.typeParam(TypeParamType(
            symbol: flowTypeParamSymbol,
            nullability: .nonNull
        )))
        let flowCollectorType = types.make(.functionType(FunctionType(
            params: [flowElementType],
            returnType: types.unitType,
            isSuspend: true,
            nullability: .nonNull
        )))
        if !bundledIndex.containsNominal(fqName: flowPkg + [interner.intern("Flow")]),
           !symbols.isSourceBackedSymbol(flowInterfaceSymbol)
        {
            let flowInterfaceMembers = coroutineMemberRows(of: flowInterfaceSymbol, type: flowRawType, symbols: symbols, interner: interner)
            flowInterfaceMembers.fn("collect", "kk_flow_collect", [(name: "collector", type: flowCollectorType)], ret: types.unitType, isSuspend: true)
            // KUU-1351: `onErrorReturn`/`onErrorResume`/`delayEach` do not exist
            // on `kotlinx.coroutines.flow.Flow`; no synthetic members are
            // registered for them so calls stay unresolved like on the JVM.
        }
    }

    func registerSuspendCoroutineUninterceptedOrReturn(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let kotlinCoroutinesIntrinsicsPkg = context.kotlinCoroutinesIntrinsicsPkg
        let continuationSymbol = context.continuationSymbol!

        let suspendIntrinsicName = interner.intern("suspendCoroutineUninterceptedOrReturn")
        let suspendIntrinsicFQName = kotlinCoroutinesIntrinsicsPkg + [suspendIntrinsicName]
        let hasBundledSuspendIntrinsic = BundledSyntheticStubRegistration.bundledIndex.contains(
            ownerFQName: kotlinCoroutinesIntrinsicsPkg,
            name: suspendIntrinsicName,
            arity: 1
        )
        if !hasBundledSuspendIntrinsic, symbols.lookup(fqName: suspendIntrinsicFQName) == nil {
            let suspendIntrinsicSymbol = symbols.define(
                kind: .function,
                name: suspendIntrinsicName,
                fqName: suspendIntrinsicFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction, .suspendFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinCoroutinesIntrinsicsPkg) {
                symbols.setParentSymbol(packageSymbol, for: suspendIntrinsicSymbol)
            }

            let functionTypeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: interner.intern("T"),
                fqName: suspendIntrinsicFQName + [interner.intern("$synthetic"), interner.intern("T")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let functionTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: functionTypeParameterSymbol,
                nullability: .nonNull
            )))
            let continuationType = types.make(.classType(ClassType(
                classSymbol: continuationSymbol,
                args: [.invariant(functionTypeParameterType)],
                nullability: .nonNull
            )))

            let blockParameterSymbol = symbols.define(
                kind: .valueParameter,
                name: interner.intern("block"),
                fqName: suspendIntrinsicFQName + [interner.intern("block")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(suspendIntrinsicSymbol, for: blockParameterSymbol)

            let blockType = types.make(.functionType(FunctionType(
                params: [continuationType],
                returnType: types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [blockType],
                    returnType: functionTypeParameterType,
                    isSuspend: true,
                    valueParameterSymbols: [blockParameterSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [functionTypeParameterSymbol]
                ),
                for: suspendIntrinsicSymbol
            )
        }

        context.hasBundledSuspendIntrinsic = hasBundledSuspendIntrinsic
    }

    func registerCancellationExceptionConstructors(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let cancellationIsSourceBacked = context.cancellationIsSourceBacked
        let cancellationSymbol = context.cancellationSymbol!
        let cancellationType = context.cancellationType!
        let throwableSymbol = context.throwableSymbol!

        if !cancellationIsSourceBacked {
            registerSyntheticPlatformExceptionConstructors(
                ownerSymbol: cancellationSymbol,
                ownerType: cancellationType,
                symbols: symbols,
                types: types,
                interner: interner,
                includeMessageOverload: true,
                throwableSymbol: throwableSymbol,
                noArgLinkName: "__kk_cancellation_exception_new",
                messageLinkName: "__kk_cancellation_exception_new_message",
                messageCauseLinkName: "__kk_cancellation_exception_new_message_cause"
            )
            let nullableThrowableType = types.make(.classType(ClassType(
                classSymbol: throwableSymbol,
                args: [],
                nullability: .nullable
            )))
            registerSyntheticPlatformExceptionConstructor(
                ownerSymbol: cancellationSymbol,
                ownerType: cancellationType,
                parameters: [("cause", nullableThrowableType)],
                externalLinkName: "__kk_cancellation_exception_new_cause",
                symbols: symbols,
                interner: interner
            )
        }
    }

    func registerCoroutineIntrinsicFunctions(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let kotlinCoroutinesIntrinsicsPkg = context.kotlinCoroutinesIntrinsicsPkg
        let coroutineSuspendedType = context.coroutineSuspendedType!
        let hasBundledSuspendIntrinsic = context.hasBundledSuspendIntrinsic
        let continuationSymbol = context.continuationSymbol!
        let cancellationPkg = context.cancellationPkg

        let coroutineSuspendedName = interner.intern("COROUTINE_SUSPENDED")
        let hasBundledCoroutineSuspended = BundledSyntheticStubRegistration.bundledIndex.contains(
            ownerFQName: kotlinCoroutinesIntrinsicsPkg,
            name: coroutineSuspendedName,
            arity: 0
        )
        if !hasBundledCoroutineSuspended {
            registerSyntheticCoroutineTopLevelProperty(
                named: "COROUTINE_SUSPENDED",
                packageFQName: kotlinCoroutinesIntrinsicsPkg,
                returnType: coroutineSuspendedType,
                externalLinkName: "kk_coroutine_suspended",
                symbols: symbols,
                interner: interner
            )
        }
        let suspendCoroutineName = interner.intern("suspendCoroutineUninterceptedOrReturn")
        let suspendCoroutineFQName = kotlinCoroutinesIntrinsicsPkg + [suspendCoroutineName]
        if !hasBundledSuspendIntrinsic, symbols.lookup(fqName: suspendCoroutineFQName) == nil {
            let suspendCoroutineTypeParamName = interner.intern("T")
            let suspendCoroutineTypeParamFQName = suspendCoroutineFQName + [suspendCoroutineTypeParamName]
            let suspendCoroutineTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: suspendCoroutineTypeParamName,
                fqName: suspendCoroutineTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let suspendCoroutineTypeParamType = types.make(.typeParam(TypeParamType(
                symbol: suspendCoroutineTypeParamSymbol,
                nullability: .nonNull
            )))
            let suspendCoroutineContinuationType = types.make(.classType(ClassType(
                classSymbol: continuationSymbol,
                args: [.invariant(suspendCoroutineTypeParamType)],
                nullability: .nonNull
            )))
            let suspendCoroutineBlockType = types.make(.functionType(FunctionType(
                params: [suspendCoroutineContinuationType],
                returnType: types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let suspendCoroutineBlockName = interner.intern("block")
            let suspendCoroutineBlockSymbol = symbols.define(
                kind: .valueParameter,
                name: suspendCoroutineBlockName,
                fqName: suspendCoroutineFQName + [suspendCoroutineBlockName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let suspendCoroutineSymbol = symbols.define(
                kind: .function,
                name: suspendCoroutineName,
                fqName: suspendCoroutineFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinCoroutinesIntrinsicsPkg) {
                symbols.setParentSymbol(packageSymbol, for: suspendCoroutineSymbol)
            }
            symbols.setParentSymbol(suspendCoroutineSymbol, for: suspendCoroutineTypeParamSymbol)
            symbols.setParentSymbol(suspendCoroutineSymbol, for: suspendCoroutineBlockSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [suspendCoroutineBlockType],
                    returnType: suspendCoroutineTypeParamType,
                    isSuspend: true,
                    valueParameterSymbols: [suspendCoroutineBlockSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [suspendCoroutineTypeParamSymbol],
                    classTypeParameterCount: 0
                ),
                for: suspendCoroutineSymbol
            )
        }

        registerSyntheticCoroutineTopLevelFunction(
            named: "cancel",
            packageFQName: cancellationPkg,
            parameters: [(name: "message", type: types.stringType)],
            returnType: types.unitType,
            externalLinkName: "kk_coroutine_cancel_current",
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticCoroutineTopLevelFunction(
            named: "cancel",
            packageFQName: cancellationPkg,
            parameters: [
                (name: "message", type: types.stringType),
                (name: "cause", type: types.makeNullable(types.anyType)),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_coroutine_cancel_current",
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )
    }
}
