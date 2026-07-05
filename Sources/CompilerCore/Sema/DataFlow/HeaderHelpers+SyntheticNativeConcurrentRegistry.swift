
/// Synthetic stdlib stubs for `kotlin.native.concurrent` (STDLIB-NATIVE-CONCURRENT-002).
///
/// Registers:
///   - `Continuation0` / `Continuation1` / `Continuation2` classes
///   - `callContinuation0` / `callContinuation1` / `callContinuation2` extensions
///   - `DetachedObjectGraph<T>` class with constructors, `asCPointer`, and `attach`
///   - `FreezingException` class with native constructor surface
///   - `InvalidMutabilityException` class with native constructor surface
///   - `WorkerBoundReference<T>` class with constructor and read-only properties
///   - `atomicLazy` top-level function
///   - `ensureNeverFrozen` top-level extension
///   - `freeze` top-level extension and `isFrozen` extension property
///   - `waitForMultipleFutures` top-level and collection-extension functions
///   - `waitWorkerTermination(worker)` top-level function
///   - `withWorker(name, errorReporting, block)` top-level function
///   - `Worker` class with `execute`, `requestTermination`, `isTerminated`, `name` members
///   - `Future<T>` class with `result`, `consume`, `getState` members and `FutureState` enum
///   - `AtomicInt`, `AtomicLong`, and `AtomicNativePtr` legacy classes
///   - `FreezableAtomicReference<T>`
///   - `MutableData`
///   - `@ObsoleteWorkersApi` marker annotation
///   - `AtomicReference<T>` (legacy alias in `kotlin.native.concurrent`)
///   - `TransferMode` enum with `SAFE` and `UNSAFE` entries
///   - `@SharedImmutable` annotation (PROPERTY target)
///   - `@ThreadLocal` annotation (PROPERTY/CLASS target, native variant)

private enum NativeConcurrentRegistrationStep: CaseIterable {
    case continuationTypes
    case callContinuationFunctions
    case detachedObjectGraph
    case freezingException
    case invalidMutabilityException
    case worker
    case workerBoundReference
    case atomicLazy
    case ensureNeverFrozen
    case freezeAndIsFrozen
    case future
    case waitForMultipleFutures
    case waitWorkerTermination
    case withWorker
    case legacyAtomicScalars
    case freezableAtomicReference
    case mutableData
    case atomicReference
    case markerAnnotations
}

extension DataFlowSemaPhase {
    func registerSyntheticNativeConcurrentStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativeConcurrentPkg = ensurePackage(
            path: ["kotlin", "native", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let nativeConcurrentPkgSymbol = symbols.lookup(fqName: nativeConcurrentPkg)

        // TransferMode enum
        let transferModeSymbol = ensureNativeConcurrentEnum(
            named: "TransferMode",
            entries: ["SAFE", "UNSAFE"],
            in: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let transferModeType = types.make(.classType(ClassType(
            classSymbol: transferModeSymbol,
            args: [],
            nullability: .nonNull
        )))
        setNativeConcurrentEnumEntryTypes(
            enumSymbol: transferModeSymbol,
            enumType: transferModeType,
            symbols: symbols
        )

        // FutureState enum
        let futureStateSymbol = ensureNativeConcurrentEnum(
            named: "FutureState",
            entries: ["SCHEDULED", "COMPUTED", "THROWN", "CANCELLED"],
            in: nativeConcurrentPkg,
            pkgSymbol: nativeConcurrentPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let futureStateType = types.make(.classType(ClassType(
            classSymbol: futureStateSymbol,
            args: [],
            nullability: .nonNull
        )))
        setNativeConcurrentEnumEntryTypes(
            enumSymbol: futureStateSymbol,
            enumType: futureStateType,
            symbols: symbols
        )

        for step in NativeConcurrentRegistrationStep.allCases {
            registerNativeConcurrentStep(
                step,
                packageFQName: nativeConcurrentPkg,
                pkgSymbol: nativeConcurrentPkgSymbol,
                transferModeType: transferModeType,
                futureStateType: futureStateType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }
}


extension DataFlowSemaPhase {
    private func registerNativeConcurrentStep(
        _ step: NativeConcurrentRegistrationStep,
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        transferModeType: TypeID,
        futureStateType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        switch step {
        case .continuationTypes:
            registerNativeConcurrentContinuationTypes(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .callContinuationFunctions:
            registerNativeConcurrentCallContinuationFunctions(
                packageFQName: packageFQName,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .detachedObjectGraph:
            registerNativeConcurrentDetachedObjectGraph(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                transferModeType: transferModeType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .freezingException:
            registerNativeConcurrentFreezingException(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .invalidMutabilityException:
            registerNativeConcurrentInvalidMutabilityException(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .worker:
            registerNativeConcurrentWorker(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                transferModeType: transferModeType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .workerBoundReference:
            registerNativeConcurrentWorkerBoundReference(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .atomicLazy:
            registerNativeConcurrentAtomicLazy(
                packageFQName: packageFQName,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .ensureNeverFrozen:
            registerNativeConcurrentEnsureNeverFrozen(
                packageFQName: packageFQName,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .freezeAndIsFrozen:
            registerNativeConcurrentFreezeAndIsFrozen(
                packageFQName: packageFQName,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .future:
            registerNativeConcurrentFuture(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                futureStateType: futureStateType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .waitForMultipleFutures:
            registerNativeConcurrentWaitForMultipleFutures(
                packageFQName: packageFQName,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .waitWorkerTermination:
            registerNativeConcurrentWaitWorkerTermination(
                packageFQName: packageFQName,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .withWorker:
            registerNativeConcurrentWithWorker(
                packageFQName: packageFQName,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .legacyAtomicScalars:
            registerNativeConcurrentLegacyAtomicScalars(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .freezableAtomicReference:
            registerNativeConcurrentFreezableAtomicReference(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .mutableData:
            registerNativeConcurrentMutableData(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .atomicReference:
            registerNativeConcurrentAtomicReference(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case .markerAnnotations:
            registerNativeConcurrentMarkerAnnotations(
                packageFQName: packageFQName,
                pkgSymbol: pkgSymbol,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerNativeConcurrentMarkerAnnotations(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let obsoleteWorkersApiSymbol = ensureAnnotationClassSymbol(
            named: "ObsoleteWorkersApi",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: obsoleteWorkersApiSymbol)
        }
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.RequiresOptIn",
                    arguments: [
                        "message = \"Workers API is obsolete and will be replaced with threads eventually\"",
                        "level = RequiresOptIn.Level.WARNING",
                    ]
                ),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.ANNOTATION_CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.FIELD",
                        "AnnotationTarget.LOCAL_VARIABLE",
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.TYPEALIAS",
                    ]
                ),
            ],
            to: obsoleteWorkersApiSymbol,
            symbols: symbols
        )

        let sharedImmutableSymbol = ensureAnnotationClassSymbol(
            named: "SharedImmutable",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: sharedImmutableSymbol)
        }
        appendNativeConcurrentAnnotationMetadata(
            to: sharedImmutableSymbol,
            targets: ["AnnotationTarget.PROPERTY"],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )

        let threadLocalNativeAnnotationSymbol = ensureAnnotationClassSymbol(
            named: "ThreadLocal",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: threadLocalNativeAnnotationSymbol)
        }
        appendNativeConcurrentAnnotationMetadata(
            to: threadLocalNativeAnnotationSymbol,
            targets: ["AnnotationTarget.PROPERTY", "AnnotationTarget.CLASS"],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Continuation0/1/2 classes and callContinuation0/1/2 extension functions.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - Continuation0 / Continuation1 / Continuation2

    func registerNativeConcurrentContinuationTypes(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nullableCOpaquePointerType = types.makeNullable(nativeConcurrentCOpaquePointerType(
            symbols: symbols,
            types: types,
            interner: interner
        ))
        let invokerCallbackType = types.make(.functionType(FunctionType(
            params: [nullableCOpaquePointerType],
            returnType: types.unitType
        )))
        let cFunctionType = nativeConcurrentCFunctionType(
            functionType: invokerCallbackType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let invokerType = nativeConcurrentCPointerType(
            pointeeType: cFunctionType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerNativeConcurrentContinuationType(
            name: "Continuation0",
            typeParameterNames: [],
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            invokerType: invokerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentContinuationType(
            name: "Continuation1",
            typeParameterNames: ["T1"],
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            invokerType: invokerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentContinuationType(
            name: "Continuation2",
            typeParameterNames: ["T1", "T2"],
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            invokerType: invokerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentContinuationType(
        name: String,
        typeParameterNames: [String],
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        invokerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let continuationName = interner.intern(name)
        let continuationFQName = packageFQName + [continuationName]
        let continuationSymbol: SymbolID
        if let existing = symbols.lookup(fqName: continuationFQName), symbols.symbol(existing)?.kind == .class {
            continuationSymbol = existing
        } else {
            continuationSymbol = symbols.define(
                kind: .class,
                name: continuationName,
                fqName: continuationFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: continuationSymbol)
        }

        let typeParameterSymbols = typeParameterNames.map { typeParameterName in
            let internedName = interner.intern(typeParameterName)
            let fqName = continuationFQName + [internedName]
            if let existing = symbols.lookup(fqName: fqName) {
                return existing
            }
            let symbol = symbols.define(
                kind: .typeParameter,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(continuationSymbol, for: symbol)
            return symbol
        }
        let typeParameterTypes = typeParameterSymbols.map { symbol in
            types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull)))
        }
        let continuationType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: typeParameterTypes.map { .invariant($0) },
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols(typeParameterSymbols, for: continuationSymbol)
        types.setNominalTypeParameterVariances(
            Array(repeating: .invariant, count: typeParameterSymbols.count),
            for: continuationSymbol
        )
        symbols.setPropertyType(continuationType, for: continuationSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["message = \"This API is deprecated without replacement\""]
                ),
            ],
            to: continuationSymbol,
            symbols: symbols
        )

        let blockType = types.make(.functionType(FunctionType(
            params: typeParameterTypes,
            returnType: types.unitType
        )))
        registerNativeConcurrentContinuationFunctionSupertype(
            ownerSymbol: continuationSymbol,
            functionArity: typeParameterTypes.count,
            functionArgumentTypes: typeParameterTypes,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentConstructor(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            parameters: [
                (name: "block", type: blockType),
                (name: "invoker", type: invokerType),
                (name: "singleShot", type: types.booleanType),
            ],
            defaultValues: [false, false, true],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: typeParameterSymbols.count,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            name: "dispose",
            returnType: types.unitType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: typeParameterSymbols.count,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            name: "invoke",
            returnType: types.unitType,
            parameters: typeParameterTypes.enumerated().map { index, type in
                (name: "p\(index + 1)", type: type)
            },
            defaultValues: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: typeParameterSymbols.count,
            flags: [.synthetic, .operatorFunction, .overrideMember, .openType],
            symbols: symbols,
            interner: interner
        )
    }

    func registerNativeConcurrentCallContinuationFunctions(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let receiverType = nativeConcurrentCOpaquePointerType(
            symbols: symbols,
            types: types,
            interner: interner
        )

        for arity in 0...2 {
            registerNativeConcurrentCallContinuationFunction(
                arity: arity,
                packageFQName: packageFQName,
                receiverType: receiverType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    private func registerNativeConcurrentCallContinuationFunction(
        arity: Int,
        packageFQName: [InternedString],
        receiverType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("callContinuation\(arity)")
        let functionFQName = packageFQName + [functionName]
        let typeParameterSymbols: [SymbolID] = arity == 0 ? [] : (1...arity).map { index in
            let typeParameterName = interner.intern("T\(index)")
            let typeParameterFQName = functionFQName + [typeParameterName]
            if let existing = symbols.lookup(fqName: typeParameterFQName) {
                return existing
            }
            let symbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            return symbol
        }

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == types.unitType
                && signature.typeParameterSymbols == typeParameterSymbols
        }) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        for typeParameterSymbol in typeParameterSymbols {
            symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
        }
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["message = \"This API is deprecated without replacement\""]
                ),
            ],
            to: functionSymbol,
            symbols: symbols
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: DetachedObjectGraph<T> class and attach extension function.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - DetachedObjectGraph<T>

    func registerNativeConcurrentDetachedObjectGraph(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        transferModeType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let graphName = interner.intern("DetachedObjectGraph")
        let graphFQName = packageFQName + [graphName]

        let graphSymbol: SymbolID
        if let existing = symbols.lookup(fqName: graphFQName), symbols.symbol(existing)?.kind == .class {
            graphSymbol = existing
        } else {
            graphSymbol = symbols.define(
                kind: .class,
                name: graphName,
                fqName: graphFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: graphSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = graphFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let graphType = types.make(.classType(ClassType(
            classSymbol: graphSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: graphSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: graphSymbol)
        symbols.setPropertyType(graphType, for: graphSymbol)

        let cOpaquePointerType = nativeConcurrentCOpaquePointerType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        let nullableCOpaquePointerType = types.makeNullable(cOpaquePointerType)
        let producerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: typeParamType
        )))

        registerNativeConcurrentConstructor(
            ownerSymbol: graphSymbol,
            ownerType: graphType,
            parameters: [
                (name: "mode", type: transferModeType),
                (name: "producer", type: producerType),
            ],
            defaultValues: [true, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentConstructor(
            ownerSymbol: graphSymbol,
            ownerType: graphType,
            parameters: [(name: "pointer", type: nullableCOpaquePointerType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: graphSymbol,
            ownerType: graphType,
            name: "asCPointer",
            returnType: nullableCOpaquePointerType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAttachExtension(
            packageFQName: packageFQName,
            graphSymbol: graphSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentAttachExtension(
        packageFQName: [InternedString],
        graphSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("attach")
        let functionFQName = packageFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: graphSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == typeParamType
        }) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: FreezingException and InvalidMutabilityException classes.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - FreezingException

    func registerNativeConcurrentFreezingException(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let exceptionName = interner.intern("FreezingException")
        let exceptionFQName = packageFQName + [exceptionName]
        let exceptionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: exceptionFQName), symbols.symbol(existing)?.kind == .class {
            exceptionSymbol = existing
        } else {
            exceptionSymbol = symbols.define(
                kind: .class,
                name: exceptionName,
                fqName: exceptionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: exceptionSymbol)
        }

        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(exceptionType, for: exceptionSymbol)

        let runtimeExceptionSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin"],
            name: "RuntimeException",
            symbols: symbols,
            interner: interner
        )
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalNativeApi")],
            to: exceptionSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: exceptionSymbol,
            ownerType: exceptionType,
            parameters: [
                (name: "toFreeze", type: types.anyType),
                (name: "blocker", type: types.anyType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - InvalidMutabilityException

    func registerNativeConcurrentInvalidMutabilityException(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let exceptionName = interner.intern("InvalidMutabilityException")
        let exceptionFQName = packageFQName + [exceptionName]
        let exceptionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: exceptionFQName), symbols.symbol(existing)?.kind == .class {
            exceptionSymbol = existing
        } else {
            exceptionSymbol = symbols.define(
                kind: .class,
                name: exceptionName,
                fqName: exceptionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: exceptionSymbol)
        }

        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(exceptionType, for: exceptionSymbol)

        let runtimeExceptionSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin"],
            name: "RuntimeException",
            symbols: symbols,
            interner: interner
        )
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalNativeApi")],
            to: exceptionSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: exceptionSymbol,
            ownerType: exceptionType,
            parameters: [(name: "message", type: types.stringType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Worker class with Companion.start, member functions, and properties.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - Worker

    func registerNativeConcurrentWorker(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        transferModeType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let workerName = interner.intern("Worker")
        let workerFQName = packageFQName + [workerName]

        let workerSymbol: SymbolID
        if let existing = symbols.lookup(fqName: workerFQName), symbols.symbol(existing)?.kind == .class {
            workerSymbol = existing
        } else {
            workerSymbol = symbols.define(
                kind: .class,
                name: workerName,
                fqName: workerFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: workerSymbol)
        }
        let workerType = types.make(.classType(ClassType(
            classSymbol: workerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(workerType, for: workerSymbol)

        // Worker companion: start(name: String? = null): Worker
        let companionName = interner.intern("Companion")
        let companionFQName = workerFQName + [companionName]
        let companionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: companionFQName) {
            companionSymbol = existing
        } else {
            companionSymbol = symbols.define(
                kind: .object,
                name: companionName,
                fqName: companionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(workerSymbol, for: companionSymbol)
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(companionType, for: companionSymbol)

        // Worker.Companion.start(name: String? = null): Worker
        registerNativeConcurrentMemberFunction(
            ownerSymbol: companionSymbol,
            ownerType: companionType,
            name: "start",
            externalLinkName: "kk_worker_new",
            returnType: workerType,
            parameters: [(name: "name", type: types.makeNullable(types.stringType))],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )

        // Worker.execute(mode: TransferMode, producer: () -> T1, job: (T1) -> T2): Future<T2>
        let executeName = interner.intern("execute")
        let executeFQName = workerFQName + [executeName]
        let executeT1Symbol = nativeConcurrentSyntheticTypeParameter(
            named: "T1",
            ownerFQName: executeFQName,
            symbols: symbols,
            interner: interner
        )
        let executeT2Symbol = nativeConcurrentSyntheticTypeParameter(
            named: "T2",
            ownerFQName: executeFQName,
            symbols: symbols,
            interner: interner
        )
        let executeT1Type = types.make(.typeParam(TypeParamType(
            symbol: executeT1Symbol,
            nullability: .nonNull
        )))
        let executeT2Type = types.make(.typeParam(TypeParamType(
            symbol: executeT2Symbol,
            nullability: .nonNull
        )))
        let executeProducerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: executeT1Type
        )))
        let executeJobType = types.make(.functionType(FunctionType(
            params: [executeT1Type],
            returnType: executeT2Type
        )))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: workerSymbol,
            ownerType: workerType,
            name: "execute",
            externalLinkName: "kk_worker_execute",
            returnType: nativeConcurrentFutureType(
                elementType: executeT2Type,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            parameters: [
                (name: "mode", type: transferModeType),
                (name: "producer", type: executeProducerType),
                (name: "job", type: executeJobType),
            ],
            defaultValues: [false, false, false],
            typeParameterSymbols: [executeT1Symbol, executeT2Symbol],
            symbols: symbols,
            interner: interner
        )

        // Worker.requestTermination(processScheduled: Boolean = true): Future<Boolean>
        registerNativeConcurrentMemberFunction(
            ownerSymbol: workerSymbol,
            ownerType: workerType,
            name: "requestTermination",
            externalLinkName: "kk_worker_request_termination",
            returnType: nativeConcurrentFutureType(
                elementType: types.booleanType,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            parameters: [(name: "processScheduled", type: types.booleanType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )

        // Worker.isTerminated: Boolean (property)
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: workerSymbol,
            name: "isTerminated",
            propertyType: types.booleanType,
            getterLinkName: "kk_worker_is_terminated",
            symbols: symbols,
            interner: interner
        )

        // Worker.name: String (property)
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: workerSymbol,
            name: "name",
            propertyType: types.stringType,
            getterLinkName: "kk_worker_name",
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: WorkerBoundReference<T> class.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - WorkerBoundReference<T>

    func registerNativeConcurrentWorkerBoundReference(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let referenceName = interner.intern("WorkerBoundReference")
        let referenceFQName = packageFQName + [referenceName]
        let referenceSymbol: SymbolID
        if let existing = symbols.lookup(fqName: referenceFQName), symbols.symbol(existing)?.kind == .class {
            referenceSymbol = existing
        } else {
            referenceSymbol = symbols.define(
                kind: .class,
                name: referenceName,
                fqName: referenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: referenceSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = referenceFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let referenceType = types.make(.classType(ClassType(
            classSymbol: referenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: referenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: referenceSymbol)
        symbols.setPropertyType(referenceType, for: referenceSymbol)

        registerNativeConcurrentConstructor(
            ownerSymbol: referenceSymbol,
            ownerType: referenceType,
            parameters: [(name: "value", type: typeParamType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: referenceSymbol,
            name: "value",
            propertyType: typeParamType,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: referenceSymbol,
            name: "valueOrNull",
            propertyType: types.makeNullable(typeParamType),
            symbols: symbols,
            interner: interner
        )

        let workerType = nativeConcurrentClassType(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Worker",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: referenceSymbol,
            name: "worker",
            propertyType: workerType,
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: atomicLazy(initializer) top-level function.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - atomicLazy

    func registerNativeConcurrentAtomicLazy(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("atomicLazy")
        let functionFQName = packageFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let initializerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: typeParamType
        )))
        let lazyType = nativeConcurrentLazyType(
            elementType: typeParamType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.parameterTypes == [initializerType]
                && signature.returnType == lazyType
        }) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }

        let initializerName = interner.intern("initializer")
        let initializerSymbol = symbols.define(
            kind: .valueParameter,
            name: initializerName,
            fqName: functionFQName + [initializerName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: initializerSymbol)
        symbols.setPropertyType(initializerType, for: initializerSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [initializerType],
                returnType: lazyType,
                isSuspend: false,
                valueParameterSymbols: [initializerSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Any.ensureNeverFrozen() extension.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - ensureNeverFrozen

    func registerNativeConcurrentEnsureNeverFrozen(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("ensureNeverFrozen")
        let functionFQName = packageFQName + [functionName]
        let receiverType = types.anyType

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == types.unitType
        }) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .throwingFunction]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                isSuspend: false,
                canThrow: true,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: `<T>.freeze()` and
/// `Any?.isFrozen` legacy-memory-manager surfaces.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - freeze / isFrozen

    func registerNativeConcurrentFreezeAndIsFrozen(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let freezeName = interner.intern("freeze")
        let freezeFQName = packageFQName + [freezeName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = freezeFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParameterSymbol)
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))

        registerNativeConcurrentPackageFunction(
            named: "freeze",
            packageFQName: packageFQName,
            receiverType: typeParameterType,
            returnType: typeParameterType,
            parameters: [],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Support for the legacy memory manager has been completely removed. Usages of this function can be safely dropped.",
                    replaceWith: "this"
                ),
            ],
            externalLinkName: "kk_freeze_object",
            symbols: symbols,
            interner: interner
        )

        registerNativeConcurrentPackageExtensionProperty(
            named: "isFrozen",
            packageFQName: packageFQName,
            receiverType: types.nullableAnyType,
            returnType: types.booleanType,
            annotations: [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Support for the legacy memory manager has been completely removed. Consequently, this property is always `false`.",
                    replaceWith: "false"
                ),
            ],
            externalLinkName: "kk_is_frozen",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerNativeConcurrentPackageExtensionProperty(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        annotations: [MetadataAnnotationRecord] = [],
        externalLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: id) == receiverType
        }) {
            symbols.setPropertyType(returnType, for: existing)
            appendNativeConcurrentMetadataAnnotations(annotations, to: existing, symbols: symbols)
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType
                    ),
                    for: getterSymbol
                )
                appendNativeConcurrentMetadataAnnotations(annotations, to: getterSymbol, symbols: symbols)
                if let externalLinkName {
                    symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
                }
            }
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        appendNativeConcurrentMetadataAnnotations(annotations, to: propertySymbol, symbols: symbols)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        }

        let getterAccessorName = interner.intern("$get")
        let getterSymbol = symbols.define(
            kind: .function,
            name: getterAccessorName,
            fqName: propertyFQName + [getterAccessorName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: getterSymbol
        )
        appendNativeConcurrentMetadataAnnotations(annotations, to: getterSymbol, symbols: symbols)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
        }
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Future<T> class with result, consume, getState members.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - Future<T>

    func registerNativeConcurrentFuture(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        futureStateType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let futureName = interner.intern("Future")
        let futureFQName = packageFQName + [futureName]

        let futureSymbol: SymbolID
        if let existing = symbols.lookup(fqName: futureFQName), symbols.symbol(existing)?.kind == .class {
            futureSymbol = existing
        } else {
            futureSymbol = symbols.define(
                kind: .class,
                name: futureName,
                fqName: futureFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: futureSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = futureFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let futureType = types.make(.classType(ClassType(
            classSymbol: futureSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: futureSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: futureSymbol)
        symbols.setPropertyType(futureType, for: futureSymbol)

        // Future.result: T
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: futureSymbol,
            name: "result",
            propertyType: typeParamType,
            getterLinkName: "kk_future_result",
            symbols: symbols,
            interner: interner
        )

        // Future.consume(): T
        registerNativeConcurrentMemberFunction(
            ownerSymbol: futureSymbol,
            ownerType: futureType,
            name: "consume",
            externalLinkName: "kk_future_consume",
            returnType: typeParamType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // Future.getState(): FutureState
        registerNativeConcurrentMemberFunction(
            ownerSymbol: futureSymbol,
            ownerType: futureType,
            name: "getState",
            externalLinkName: "kk_future_getState",
            returnType: futureStateType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: waitForMultipleFutures(...) top-level and Collection extension.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - waitForMultipleFutures

    func registerNativeConcurrentWaitForMultipleFutures(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("waitForMultipleFutures")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let futureType = nativeConcurrentFutureType(
            elementType: typeParameterType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let futuresCollectionType = nativeConcurrentCollectionType(
            named: "Collection",
            elementType: futureType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let futureSetType = nativeConcurrentCollectionType(
            named: "Set",
            elementType: futureType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerNativeConcurrentPackageFunction(
            named: "waitForMultipleFutures",
            packageFQName: packageFQName,
            receiverType: nil,
            returnType: futureSetType,
            parameters: [
                (name: "futures", type: futuresCollectionType),
                (name: "timeoutMillis", type: types.intType),
            ],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
            ],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentPackageFunction(
            named: "waitForMultipleFutures",
            packageFQName: packageFQName,
            receiverType: futuresCollectionType,
            returnType: futureSetType,
            parameters: [(name: "millis", type: types.intType)],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Use 'waitForMultipleFutures' top-level function instead\"",
                        "replaceWith = \"waitForMultipleFutures(this, millis)\"",
                        "level = DeprecationLevel.ERROR",
                    ]
                ),
            ],
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: waitWorkerTermination(worker) top-level function.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - waitWorkerTermination

    func registerNativeConcurrentWaitWorkerTermination(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let workerType = nativeConcurrentClassType(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Worker",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentPackageFunction(
            named: "waitWorkerTermination",
            packageFQName: packageFQName,
            receiverType: nil,
            returnType: types.unitType,
            parameters: [(name: "worker", type: workerType)],
            typeParameterSymbols: [],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
            ],
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: withWorker(name, errorReporting, block) top-level function.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - withWorker

    func registerNativeConcurrentWithWorker(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("withWorker")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("R")
        let typeParameterFQName = functionFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let workerType = nativeConcurrentClassType(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Worker",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let blockType = types.make(.functionType(FunctionType(
            receiver: workerType,
            params: [],
            returnType: typeParameterType
        )))

        registerNativeConcurrentPackageFunction(
            named: "withWorker",
            packageFQName: packageFQName,
            receiverType: nil,
            returnType: typeParameterType,
            parameters: [
                (name: "name", type: types.makeNullable(types.stringType)),
                (name: "errorReporting", type: types.booleanType),
                (name: "block", type: blockType),
            ],
            defaultValues: [true, true, false],
            typeParameterSymbols: [typeParameterSymbol],
            annotations: [
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ObsoleteWorkersApi"),
            ],
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: AtomicInt / AtomicLong / AtomicNativePtr legacy scalar classes.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - AtomicInt / AtomicLong / AtomicNativePtr

    func registerNativeConcurrentLegacyAtomicScalars(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerNativeConcurrentLegacyAtomicInt(
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentLegacyAtomicLong(
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentLegacyAtomicNativePtr(
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicInt(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let atomicType = registerNativeConcurrentLegacyAtomicClass(
            named: "AtomicInt",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            valueType: types.intType,
            constructorDefault: false,
            replacement: "kotlin.concurrent.atomics.AtomicInt",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ownerSymbol = atomicType.classSymbol
        let ownerType = types.make(.classType(atomicType))
        registerNativeConcurrentAtomicNumericMembers(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: types.intType,
            addAndGetParameterTypes: [types.intType],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicLong(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let atomicType = registerNativeConcurrentLegacyAtomicClass(
            named: "AtomicLong",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            valueType: types.longType,
            constructorDefault: true,
            replacement: "kotlin.concurrent.atomics.AtomicLong",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ownerSymbol = atomicType.classSymbol
        let ownerType = types.make(.classType(atomicType))
        registerNativeConcurrentAtomicNumericMembers(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            valueType: types.longType,
            addAndGetParameterTypes: [types.intType, types.longType],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicNativePtr(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePtrType = nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "NativePtr",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let atomicType = registerNativeConcurrentLegacyAtomicClass(
            named: "AtomicNativePtr",
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            valueType: nativePtrType,
            constructorDefault: false,
            replacement: "kotlin.concurrent.atomics.AtomicNativePtr",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let ownerSymbol = atomicType.classSymbol
        let ownerType = types.make(.classType(atomicType))
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSet",
            returnType: types.booleanType,
            parameters: [
                (name: "expected", type: nativePtrType),
                (name: "newValue", type: nativePtrType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSwap",
            returnType: nativePtrType,
            parameters: [
                (name: "expected", type: nativePtrType),
                (name: "newValue", type: nativePtrType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndSet",
            returnType: nativePtrType,
            parameters: [(name: "newValue", type: nativePtrType)],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentToStringMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentLegacyAtomicClass(
        named name: String,
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        valueType: TypeID,
        constructorDefault: Bool,
        replacement: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> ClassType {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName), symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }

        let classType = ClassType(classSymbol: classSymbol, args: [], nullability: .nonNull)
        let ownerType = types.make(.classType(classType))
        symbols.setPropertyType(ownerType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Use \(replacement) instead.",
                    replaceWith: replacement
                ),
            ],
            to: classSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            parameters: [(name: "value", type: valueType)],
            defaultValues: [constructorDefault],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMutableProperty(
            ownerSymbol: classSymbol,
            name: "value",
            propertyType: valueType,
            symbols: symbols,
            interner: interner
        )
        return classType
    }

    private func registerNativeConcurrentAtomicNumericMembers(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        addAndGetParameterTypes: [TypeID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSet",
            returnType: types.booleanType,
            parameters: [(name: "expected", type: valueType), (name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "compareAndSwap",
            returnType: valueType,
            parameters: [(name: "expected", type: valueType), (name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndSet",
            returnType: valueType,
            parameters: [(name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        for parameterType in addAndGetParameterTypes {
            registerNativeConcurrentAtomicCoreMember(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                name: "addAndGet",
                returnType: valueType,
                parameters: [(name: "delta", type: parameterType)],
                symbols: symbols,
                interner: interner
            )
        }
        registerNativeConcurrentAtomicCoreMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "getAndAdd",
            returnType: valueType,
            parameters: [(name: "delta", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        for name in ["getAndIncrement", "getAndDecrement", "incrementAndGet", "decrementAndGet"] {
            registerNativeConcurrentAtomicCoreMember(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                name: name,
                returnType: valueType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }
        for name in ["increment", "decrement"] {
            registerNativeConcurrentAtomicCoreMember(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                name: name,
                returnType: types.unitType,
                parameters: [],
                symbols: symbols,
                interner: interner
            )
        }
        registerNativeConcurrentToStringMember(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentAtomicCoreMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerNativeConcurrentMemberFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: name,
            returnType: returnType,
            parameters: parameters,
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
    }

    func registerNativeConcurrentToStringMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerNativeConcurrentMemberFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: "toString",
            returnType: types.stringType,
            parameters: [],
            defaultValues: [],
            flags: [.synthetic, .overrideMember, .openType],
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: FreezableAtomicReference<T> class.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - FreezableAtomicReference<T>

    func registerNativeConcurrentFreezableAtomicReference(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("FreezableAtomicReference")
        let classFQName = packageFQName + [className]

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName), symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = classFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classSymbol, for: typeParamSymbol)
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        symbols.setPropertyType(classType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                nativeConcurrentDeprecatedErrorAnnotation(
                    message: "Use kotlin.concurrent.atomics.AtomicReference instead.",
                    replaceWith: "kotlin.concurrent.atomics.AtomicReference"
                ),
            ],
            to: classSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            externalLinkName: "kk_freezable_atomic_ref_create",
            parameters: [(name: "value", type: typeParamType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMutableProperty(
            ownerSymbol: classSymbol,
            name: "value",
            propertyType: typeParamType,
            getterLinkName: "kk_freezable_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "compareAndSet",
            externalLinkName: "kk_freezable_atomic_ref_compareAndSet",
            returnType: types.booleanType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "newValue", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "compareAndSwap",
            externalLinkName: "kk_freezable_atomic_ref_compareAndSwap",
            returnType: typeParamType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "newValue", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentToStringMember(
            ownerSymbol: classSymbol,
            ownerType: classType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: MutableData class with append/copyInto/withBufferLocked/withPointerLocked.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - MutableData

    func registerNativeConcurrentMutableData(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("MutableData")
        let classFQName = packageFQName + [className]

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName), symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Support for the legacy memory manager has been completely removed. Use any regular collection instead.\"",
                        "level = DeprecationLevel.ERROR",
                    ]
                ),
            ],
            to: classSymbol,
            symbols: symbols
        )

        let byteArrayType = nativeConcurrentClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let cOpaquePointerType = nativeConcurrentCOpaquePointerType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        let nullableCOpaquePointerType = types.makeNullable(cOpaquePointerType)

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameters: [(name: "capacity", type: types.intType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: classSymbol,
            name: "size",
            propertyType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "append",
            returnType: types.unitType,
            parameters: [(name: "data", type: classType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "append",
            returnType: types.unitType,
            parameters: [
                (name: "data", type: nullableCOpaquePointerType),
                (name: "count", type: types.intType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "append",
            returnType: types.unitType,
            parameters: [
                (name: "data", type: byteArrayType),
                (name: "fromIndex", type: types.intType),
                (name: "toIndex", type: types.intType),
            ],
            defaultValues: [false, true, true],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "copyInto",
            returnType: types.unitType,
            parameters: [
                (name: "output", type: byteArrayType),
                (name: "destinationIndex", type: types.intType),
                (name: "startIndex", type: types.intType),
                (name: "endIndex", type: types.intType),
            ],
            defaultValues: [false, false, false, false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "get",
            returnType: types.intType,
            parameters: [(name: "index", type: types.intType)],
            defaultValues: [false],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "reset",
            returnType: types.unitType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )

        registerNativeConcurrentMutableDataLockedMember(
            ownerSymbol: classSymbol,
            ownerType: classType,
            ownerFQName: classFQName,
            name: "withBufferLocked",
            blockParameterTypes: [byteArrayType, types.intType],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentMutableDataLockedMember(
            ownerSymbol: classSymbol,
            ownerType: classType,
            ownerFQName: classFQName,
            name: "withPointerLocked",
            blockParameterTypes: [cOpaquePointerType, types.intType],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentMutableDataLockedMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        ownerFQName: [InternedString],
        name: String,
        blockParameterTypes: [TypeID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let typeParameterSymbol = nativeConcurrentSyntheticTypeParameter(
            named: "R",
            ownerFQName: ownerFQName + [interner.intern(name)],
            symbols: symbols,
            interner: interner
        )
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            params: blockParameterTypes,
            returnType: typeParameterType
        )))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: name,
            returnType: typeParameterType,
            parameters: [(name: "block", type: blockType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
    }
}

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Legacy AtomicReference<T> class under kotlin.native.concurrent.
///
/// Consolidated into the RF-STUB-004 NativeConcurrent registry.
extension DataFlowSemaPhase {

    // MARK: - AtomicReference<T> (legacy kotlin.native.concurrent)

    func registerNativeConcurrentAtomicReference(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let atomicRefName = interner.intern("AtomicReference")
        let atomicRefFQName = packageFQName + [atomicRefName]

        let atomicRefSymbol: SymbolID
        if let existing = symbols.lookup(fqName: atomicRefFQName), symbols.symbol(existing)?.kind == .class {
            atomicRefSymbol = existing
        } else {
            atomicRefSymbol = symbols.define(
                kind: .class,
                name: atomicRefName,
                fqName: atomicRefFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: atomicRefSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = atomicRefFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let atomicRefType = types.make(.classType(ClassType(
            classSymbol: atomicRefSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: atomicRefSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: atomicRefSymbol)
        symbols.setPropertyType(atomicRefType, for: atomicRefSymbol)

        // constructor(value: T): AtomicReference<T>
        let initName = interner.intern("<init>")
        let initFQName = atomicRefFQName + [initName]
        if symbols.lookupAll(fqName: initFQName).isEmpty {
            let initSymbol = symbols.define(
                kind: .function,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(atomicRefSymbol, for: initSymbol)
            symbols.setExternalLinkName("kk_native_atomic_ref_create", for: initSymbol)
            let paramName = interner.intern("value")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: initFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: paramSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [typeParamType],
                    returnType: atomicRefType,
                    isSuspend: false,
                    valueParameterSymbols: [paramSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        // value property: var T
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: atomicRefSymbol,
            name: "value",
            propertyType: typeParamType,
            getterLinkName: "kk_native_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )

        // compareAndSwap(expected: T, new: T): T
        registerNativeConcurrentMemberFunction(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            name: "compareAndSwap",
            externalLinkName: "kk_native_atomic_ref_compareAndSwap",
            returnType: typeParamType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "new", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // compareAndSet(expected: T, new: T): Boolean
        let boolType = types.make(.primitive(.boolean, .nonNull))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            name: "compareAndSet",
            externalLinkName: "kk_native_atomic_ref_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "expected", type: typeParamType),
                (name: "new", type: typeParamType),
            ],
            defaultValues: [false, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
    }
}
