
/// Residual `WeakReference<T>` members are retained as a no-op fallback now
/// that the constructor (KSP-1255) and members (KSP-1256) are source-backed
/// in Weak.kt; the bundled-declaration check short-circuits registration.
///
/// `kotlin.native.runtime.GC` needs no stub here: it is fully source-backed
/// (see GC.kt), including its own `@NativeRuntimeApi` annotation, so it is
/// registered by ordinary header collection like any other bundled object.
///
/// `kotlin.native.runtime.Debugging` is fully source-backed (KSP-1260,
/// `Stdlib/kotlin/native/runtime/Debugging.kt`) and registers no synthetic
/// stub here.
extension DataFlowSemaPhase {
    func registerSyntheticNativeRefRuntimeStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativeRefPkg = ensurePackage(
            path: ["kotlin", "native", "ref"],
            symbols: symbols,
            interner: interner
        )
        let nativeRuntimePkg = ensurePackage(
            path: ["kotlin", "native", "runtime"],
            symbols: symbols,
            interner: interner
        )

        let experimentalNativeApiSymbol = lookupOrRegisterExperimentalNativeApiAnnotation(
            symbols: symbols,
            interner: interner
        )
        let nativeRuntimeApiSymbol = symbols.lookup(
            fqName: nativeRuntimePkg + [interner.intern("NativeRuntimeApi")]
        )

        ensureExperimentalNativeApiRequiresOptIn(
            markerSymbol: experimentalNativeApiSymbol,
            symbols: symbols
        )

        registerWeakReferenceStub(
            packageFQName: nativeRefPkg,
            experimentalNativeApiSymbol: experimentalNativeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCreateCleanerStub(
            packageFQName: nativeRefPkg,
            experimentalNativeApiSymbol: experimentalNativeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerRootSetStatisticsStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSweepStatisticsStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerGCInfoStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

    }

    private func registerWeakReferenceStub(
        packageFQName: [InternedString],
        experimentalNativeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("WeakReference")
        let classFQName = packageFQName + [className]
        let pkgSymbol = symbols.lookup(fqName: packageFQName)

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
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

        // The `@ExperimentalNativeApi` marker is declared in bundled Kotlin
        // source, so fall back to its fully-qualified name when the symbol
        // is not yet registered at synthetic-stub time.
        attachExperimentalNativeApi(
            to: classSymbol,
            markerFQName: experimentalNativeApiSymbol.flatMap {
                symbols.symbol($0)?.fqName.map { interner.resolve($0) }.joined(separator: ".")
            } ?? "kotlin.experimental.ExperimentalNativeApi",
            symbols: symbols
        )

        let typeParamSymbol = ensureSyntheticTypeParameterSymbol(
            named: "T",
            in: classFQName,
            symbols: symbols,
            interner: interner
        )
        symbols.setParentSymbol(classSymbol, for: typeParamSymbol)

        let tType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let ownerType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(tType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: classSymbol)
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)

        let weakReferenceContext = SyntheticStubRegistrationContext(
            ownerFQName: classFQName,
            parentSymbol: classSymbol,
            typeParameterSymbolsByName: ["T": typeParamSymbol]
        )
        // KSP-1255: the public constructor is now source-backed in Weak.kt
        // (`@KsSymbolName("kk_weak_ref_create") constructor(referred: T)`);
        // no synthetic constructor registration is needed here anymore.
        registerSyntheticFunctionStubs(
            SyntheticNativeRefRuntimeSurfaceSpec.weakReferenceMembers,
            context: weakReferenceContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerCreateCleanerStub(
        packageFQName: [InternedString],
        experimentalNativeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("createCleaner")
        let functionFQName = packageFQName + [functionName]
        let pkgSymbol = symbols.lookup(fqName: packageFQName)

        // KSP-1254 supplies the exact generic source declaration. Keep the
        // runtime bridge only for configurations that do not load bundled
        // Kotlin source; do not leave an Any-based synthetic duplicate beside
        // the source-backed function.
        guard !BundledSyntheticStubRegistration.bundledIndex.contains(
            ownerFQName: packageFQName,
            name: functionName,
            arity: 2
        ) else {
            return
        }

        guard symbols.lookupAll(fqName: functionFQName).isEmpty else {
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
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_cleaner_create", for: functionSymbol)

        // The `@ExperimentalNativeApi` marker is declared in bundled Kotlin
        // source, so fall back to its fully-qualified name when the symbol
        // is not yet registered at synthetic-stub time.
        attachExperimentalNativeApi(
            to: functionSymbol,
            markerFQName: experimentalNativeApiSymbol.flatMap {
                symbols.symbol($0)?.fqName.map { interner.resolve($0) }.joined(separator: ".")
            } ?? "kotlin.experimental.ExperimentalNativeApi",
            symbols: symbols
        )

        // Legacy fallback only. The bundled source declaration carries the
        // exact generic T and Cleaner signature whenever it is available.
        let anyType = types.anyType
        let blockType = types.make(.functionType(FunctionType(
            params: [anyType],
            returnType: types.unitType
        )))

        let parameterSpecs: [(name: String, type: TypeID)] = [
            ("value", anyType),
            ("block", blockType),
        ]
        var valueParameterSymbols: [SymbolID] = []
        for spec in parameterSpecs {
            let paramName = interner.intern(spec.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterSpecs.map(\.type),
                returnType: anyType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSpecs.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSpecs.count)
            ),
            for: functionSymbol
        )
    }

    private func registerRootSetStatisticsStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let classSymbol = ensureNativeRuntimeClassStub(
            named: "RootSetStatistics",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        attachNativeRuntimeApi(
            to: classSymbol,
            markerFQName: nativeRuntimeApiSymbol.flatMap {
                symbols.symbol($0)?.fqName.map { interner.resolve($0) }.joined(separator: ".")
            } ?? "kotlin.native.runtime.NativeRuntimeApi",
            symbols: symbols
        )
    }

    private func registerSweepStatisticsStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let classSymbol = ensureNativeRuntimeClassStub(
            named: "SweepStatistics",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        attachNativeRuntimeApi(
            to: classSymbol,
            markerFQName: nativeRuntimeApiSymbol.flatMap {
                symbols.symbol($0)?.fqName.map { interner.resolve($0) }.joined(separator: ".")
            } ?? "kotlin.native.runtime.NativeRuntimeApi",
            symbols: symbols
        )

    }

    private func registerGCInfoStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let gcInfoSymbol = ensureNativeRuntimeClassStub(
            named: "GCInfo",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        _ = ensureNativeRuntimeClassStub(
            named: "RootSetStatistics",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        _ = ensureNativeRuntimeClassStub(
            named: "SweepStatistics",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let memoryUsageSymbol = ensureNativeRuntimeClassStub(
            named: "MemoryUsage",
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let nativeRuntimeApiFQName = nativeRuntimeApiSymbol.flatMap {
            symbols.symbol($0)?.fqName.map { interner.resolve($0) }.joined(separator: ".")
        } ?? "kotlin.native.runtime.NativeRuntimeApi"
        attachNativeRuntimeApi(
            to: gcInfoSymbol,
            markerFQName: nativeRuntimeApiFQName,
            symbols: symbols
        )
        attachNativeRuntimeApi(
            to: memoryUsageSymbol,
            markerFQName: nativeRuntimeApiFQName,
            symbols: symbols
        )

    }

    /// Safe to call multiple times.
    private func ensureExperimentalNativeApiRequiresOptIn(
        markerSymbol: SymbolID?,
        symbols: SymbolTable
    ) {
        guard let markerSymbol else {
            return
        }
        let requiresOptInRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn"
        )
        if symbols.deferUntilAfterImportedShellMaterializes(markerSymbol, work: { [self] in
            ensureExperimentalNativeApiRequiresOptIn(markerSymbol: markerSymbol, symbols: symbols)
        }) {
            return
        }
        var annotations = symbols.annotations(for: markerSymbol)
        guard !annotations.contains(where: { $0.annotationFQName == requiresOptInRecord.annotationFQName }) else {
            return
        }
        annotations.append(requiresOptInRecord)
        symbols.setAnnotations(annotations, for: markerSymbol)
    }

    private func lookupOrRegisterExperimentalNativeApiAnnotation(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = ["kotlin", "experimental", "ExperimentalNativeApi"]
            .map { interner.intern($0) }
        return symbols.lookup(fqName: fqName)
    }

    private func attachExperimentalNativeApi(
        to symbol: SymbolID,
        markerFQName: String,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(
            annotationFQName: markerFQName.isEmpty
                ? "kotlin.experimental.ExperimentalNativeApi"
                : markerFQName
        )
        if symbols.deferUntilAfterImportedShellMaterializes(symbol, work: { [self] in
            attachExperimentalNativeApi(to: symbol, markerFQName: markerFQName, symbols: symbols)
        }) {
            return
        }
        var annotations = symbols.annotations(for: symbol)
        guard !annotations.contains(record) else {
            return
        }
        annotations.append(record)
        symbols.setAnnotations(annotations, for: symbol)
    }

    private func attachNativeRuntimeApi(
        to symbol: SymbolID,
        markerFQName: String,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(
            annotationFQName: markerFQName.isEmpty
                ? "kotlin.native.runtime.NativeRuntimeApi"
                : markerFQName
        )
        if symbols.deferUntilAfterImportedShellMaterializes(symbol, work: { [self] in
            attachNativeRuntimeApi(to: symbol, markerFQName: markerFQName, symbols: symbols)
        }) {
            return
        }
        var annotations = symbols.annotations(for: symbol)
        guard !annotations.contains(record) else {
            return
        }
        annotations.append(record)
        symbols.setAnnotations(annotations, for: symbol)
    }

    private func ensureNativeRuntimeClassStub(
        named name: String,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
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
        if let pkgSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }
        symbols.setPropertyType(nominalType(classSymbol, types: types), for: classSymbol)
        return classSymbol
    }
}
