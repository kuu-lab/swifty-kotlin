
/// STDLIB-NATIVE-REF-002: Synthetic sema stubs for `kotlin.native.ref` and
/// `kotlin.native.runtime`.
///
/// Exposes the following symbols at the sema level so that name-resolution,
/// type-checking, and opt-in diagnostics work correctly without any runtime
/// edits:
///
/// - `kotlin.native.ref.WeakReference<T>` — generic weak-reference wrapper.
/// - `kotlin.native.ref.createCleaner` — top-level factory function tagged
///   with `@ExperimentalNativeApi`.
/// - `kotlin.native.runtime.NativeRuntimeApi` — runtime opt-in marker.
/// - `kotlin.native.runtime.GC` — object providing GC controls, tagged with
///   `@NativeRuntimeApi`.
/// - `kotlin.native.runtime.RootSetStatistics` — GC root-set statistics DTO.
/// - `kotlin.native.runtime.SweepStatistics` — GC sweep statistics DTO.
/// - `kotlin.native.runtime.GCInfo` — GC statistics DTO surface.
/// - `kotlin.native.runtime.Debugging` — object exposing debug helpers, tagged
///   with `@NativeRuntimeApi`.
///
/// All symbols are compile-time stubs only.  No runtime code is generated or
/// modified by this registration.
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
        let nativeRuntimeApiSymbol = registerNativeRuntimeApiAnnotation(
            packageFQName: nativeRuntimePkg,
            symbols: symbols,
            interner: interner
        )

        // Ensure ExperimentalNativeApi is a RequiresOptIn marker so that
        // opt-in diagnostics fire when symbols tagged with it are used.
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

        registerGCObjectStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
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

        registerDebuggingObjectStub(
            packageFQName: nativeRuntimePkg,
            nativeRuntimeApiSymbol: nativeRuntimeApiSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - WeakReference<T>

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

        // Tag WeakReference itself with @ExperimentalNativeApi so that
        // callers must opt in.
        if let experimentalNativeApiSymbol {
            attachExperimentalNativeApi(
                to: classSymbol,
                markerFQName: symbols.symbol(experimentalNativeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        // Set up the single type-parameter T (inline, as the NativeInterop
        // helper is private).
        let parameterInternedName = interner.intern("T")
        let typeParameterFQName = classFQName + [parameterInternedName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: parameterInternedName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
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
        registerSyntheticConstructorStubs(
            [SyntheticNativeRefRuntimeSurfaceSpec.weakReferenceConstructor],
            ownerType: SyntheticNativeRefRuntimeSurfaceSpec.weakReferenceType,
            context: weakReferenceContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticFunctionStubs(
            SyntheticNativeRefRuntimeSurfaceSpec.weakReferenceMembers,
            context: weakReferenceContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - createCleaner

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

        // Avoid double-registration.
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

        // Tag with @ExperimentalNativeApi.
        if let experimentalNativeApiSymbol {
            attachExperimentalNativeApi(
                to: functionSymbol,
                markerFQName: symbols.symbol(experimentalNativeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        // createCleaner<T>(value: T, block: (T) -> Unit): Cleaner
        // We use `Any` as a simple approximation for T and the Cleaner return type.
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

    // MARK: - GC object

    private func registerGCObjectStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let objectName = interner.intern("GC")
        let objectFQName = packageFQName + [objectName]
        let pkgSymbol = symbols.lookup(fqName: packageFQName)

        let objectSymbol: SymbolID
        if let existing = symbols.lookup(fqName: objectFQName) {
            objectSymbol = existing
        } else {
            objectSymbol = symbols.define(
                kind: .object,
                name: objectName,
                fqName: objectFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: objectSymbol)
        }

        let objectType = types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(objectType, for: objectSymbol)

        // Tag with @NativeRuntimeApi.
        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: objectSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        let objectContext = SyntheticStubRegistrationContext(
            ownerFQName: objectFQName,
            parentSymbol: objectSymbol
        )
        registerSyntheticFunctionStubs(
            SyntheticNativeRefRuntimeSurfaceSpec.gcFunctions,
            context: objectContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticPropertyStubs(
            SyntheticNativeRefRuntimeSurfaceSpec.gcProperties,
            context: objectContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - RootSetStatistics class

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
        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: classSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        let classFQName = packageFQName + [interner.intern("RootSetStatistics")]
        let classContext = SyntheticStubRegistrationContext(
            ownerFQName: classFQName,
            parentSymbol: classSymbol
        )
        registerSyntheticConstructorStubs(
            [SyntheticNativeRefRuntimeSurfaceSpec.rootSetStatisticsConstructor],
            ownerType: SyntheticNativeRefRuntimeSurfaceSpec.rootSetStatisticsType,
            context: classContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticPropertyStubs(
            SyntheticNativeRefRuntimeSurfaceSpec.rootSetStatisticsProperties,
            context: classContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - SweepStatistics class

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
        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: classSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        let classFQName = packageFQName + [interner.intern("SweepStatistics")]
        let classContext = SyntheticStubRegistrationContext(
            ownerFQName: classFQName,
            parentSymbol: classSymbol
        )
        registerSyntheticConstructorStubs(
            [SyntheticNativeRefRuntimeSurfaceSpec.sweepStatisticsConstructor],
            ownerType: SyntheticNativeRefRuntimeSurfaceSpec.sweepStatisticsType,
            context: classContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticPropertyStubs(
            SyntheticNativeRefRuntimeSurfaceSpec.sweepStatisticsProperties,
            context: classContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - GCInfo class

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

        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: gcInfoSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
            attachNativeRuntimeApi(
                to: memoryUsageSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        let gcInfoFQName = packageFQName + [interner.intern("GCInfo")]
        let memoryUsageFQName = packageFQName + [interner.intern("MemoryUsage")]
        let gcInfoContext = SyntheticStubRegistrationContext(
            ownerFQName: gcInfoFQName,
            parentSymbol: gcInfoSymbol
        )
        registerSyntheticConstructorStubs(
            [SyntheticNativeRefRuntimeSurfaceSpec.gcInfoConstructor],
            ownerType: SyntheticNativeRefRuntimeSurfaceSpec.gcInfoType,
            context: gcInfoContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticPropertyStubs(
            SyntheticNativeRefRuntimeSurfaceSpec.gcInfoProperties,
            context: gcInfoContext,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let memoryUsageContext = SyntheticStubRegistrationContext(
            ownerFQName: memoryUsageFQName,
            parentSymbol: memoryUsageSymbol
        )
        registerSyntheticConstructorStubs(
            [SyntheticNativeRefRuntimeSurfaceSpec.memoryUsageConstructor],
            ownerType: SyntheticNativeRefRuntimeSurfaceSpec.memoryUsageType,
            context: memoryUsageContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticPropertyStubs(
            SyntheticNativeRefRuntimeSurfaceSpec.memoryUsageProperties,
            context: memoryUsageContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - Debugging object

    private func registerDebuggingObjectStub(
        packageFQName: [InternedString],
        nativeRuntimeApiSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let objectName = interner.intern("Debugging")
        let objectFQName = packageFQName + [objectName]
        let pkgSymbol = symbols.lookup(fqName: packageFQName)

        let objectSymbol: SymbolID
        if let existing = symbols.lookup(fqName: objectFQName) {
            objectSymbol = existing
        } else {
            objectSymbol = symbols.define(
                kind: .object,
                name: objectName,
                fqName: objectFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: objectSymbol)
        }

        let objectType = types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(objectType, for: objectSymbol)

        // Tag with @NativeRuntimeApi.
        if let nativeRuntimeApiSymbol {
            attachNativeRuntimeApi(
                to: objectSymbol,
                markerFQName: symbols.symbol(nativeRuntimeApiSymbol)?
                    .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "",
                symbols: symbols
            )
        }

        let objectContext = SyntheticStubRegistrationContext(
            ownerFQName: objectFQName,
            parentSymbol: objectSymbol
        )
        registerSyntheticPropertyStubs(
            SyntheticNativeRefRuntimeSurfaceSpec.debuggingProperties,
            context: objectContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    /// Attaches `@RequiresOptIn` to `ExperimentalNativeApi` so the opt-in
    /// machinery treats it as an opt-in marker.  Safe to call multiple times.
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
        var annotations = symbols.annotations(for: markerSymbol)
        guard !annotations.contains(where: { $0.annotationFQName == requiresOptInRecord.annotationFQName }) else {
            return
        }
        annotations.append(requiresOptInRecord)
        symbols.setAnnotations(annotations, for: markerSymbol)
    }

    /// Returns the `kotlin.experimental.ExperimentalNativeApi` annotation
    /// class symbol, looking it up from an earlier registration.
    private func lookupOrRegisterExperimentalNativeApiAnnotation(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = ["kotlin", "experimental", "ExperimentalNativeApi"]
            .map { interner.intern($0) }
        return symbols.lookup(fqName: fqName)
    }

    private func registerNativeRuntimeApiAnnotation(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "NativeRuntimeApi",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSymbol, for: annotationSymbol)
        }

        var annotations = symbols.annotations(for: annotationSymbol)
        let requiresOptInRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: ["level=RequiresOptIn.Level.ERROR"]
        )
        if !annotations.contains(requiresOptInRecord) {
            annotations.append(requiresOptInRecord)
        }

        let targetRecord = MetadataAnnotationRecord(
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
        )
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
        }

        let retentionRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Retention",
            arguments: ["AnnotationRetention.BINARY"]
        )
        if !annotations.contains(retentionRecord) {
            annotations.append(retentionRecord)
        }
        symbols.setAnnotations(annotations, for: annotationSymbol)
        return annotationSymbol
    }

    /// Attaches a `@ExperimentalNativeApi` annotation record to the given
    /// symbol so that opt-in checks fire when the symbol is used.
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
        var annotations = symbols.annotations(for: symbol)
        guard !annotations.contains(record) else {
            return
        }
        annotations.append(record)
        symbols.setAnnotations(annotations, for: symbol)
    }

    /// Attaches a `@NativeRuntimeApi` annotation record to a runtime symbol.
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
