import RuntimeABI

/// Synthetic stdlib stubs for kotlin's not-yet-implemented helper and kotlin.io.readLine (STDLIB-063).
/// These stubs enable name resolution and type checking; runtime behavior is implemented in Runtime.
extension DataFlowSemaPhase {
    func registerSyntheticTODOAndIOStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let kotlinPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin")],
            symbols: symbols
        )
        let kotlinIOPkg = ensureSyntheticPackageHierarchy(fqName: [interner.intern("kotlin"), interner.intern("io")], symbols: symbols)

        registerSyntheticIOTopLevelProperty(
            named: "DEFAULT_BUFFER_SIZE",
            packageFQName: kotlinIOPkg,
            returnType: types.intType,
            externalLinkName: "kk_io_default_buffer_size",
            constValue: .intLiteral(8192),
            symbols: symbols,
            interner: interner
        )

        // KSP-614: print / println are implemented in Stdlib/kotlin/io/Console.kt.
        // KSP-615: readLine / readln / readlnOrNull are implemented in Stdlib/kotlin/io/Console.kt.

        // --- Sequence factory functions (STDLIB-097) ---
        let kotlinSequencesPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("sequences")],
            symbols: symbols
        )
        _ = registerSyntheticSequenceStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticSequenceBuilderStub(
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Sequence factory functions are source-backed (KSP-651).
        // STDLIB-331/564: iterator {} builder → Iterator<T>
        // Registered with SequenceScope<T> receiver so yield() resolves inside the lambda.
        registerSyntheticIteratorBuilderStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // STDLIB-330: sequence { yield(x) } builder
        registerSyntheticSequenceBuilderStub(
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticSequenceResidualMembers(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinSequencesPkg: kotlinSequencesPkg
        )

        // --- kotlin.system package functions (STDLIB-131/132) ---
        let kotlinSystemPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("system")],
            symbols: symbols
        )

        // KSP-617: exitProcess / getTime* / measureTime* are declared in bundled
        // Kotlin source (Stdlib/kotlin/system/), so no synthetic stub is registered.

        // --- kotlin.system.System object (STDLIB-131) ---
        let systemSymbol = ensureSyntheticObjectSymbol(
            named: "System",
            in: kotlinSystemPkg,
            symbols: symbols,
            interner: interner
        )
        let systemType = types.make(.classType(ClassType(
            classSymbol: systemSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(systemType, for: systemSymbol)
        registerSyntheticSystemMember(
            ownerSymbol: systemSymbol,
            ownerType: systemType,
            name: "currentTimeMillis",
            externalLinkName: "__kk_system_currentTimeMillis",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: systemSymbol,
            ownerType: systemType,
            name: "nanoTime",
            externalLinkName: "__kk_system_nanoTime",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: systemSymbol,
            ownerType: systemType,
            name: "processStartNanos",
            externalLinkName: "__kk_system_process_start_nanos",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.native.Platform (STDLIB-NATIVE-169) ---
        let kotlinNativePkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("native")],
            symbols: symbols
        )
        // KSP-1210: use the bundled declaration when available so enum entry
        // order and generated enum APIs come from the Kotlin source contract.
        let osFamilyFQName = kotlinNativePkg + [interner.intern("OsFamily")]
        let osFamilySymbol = symbols.lookup(fqName: osFamilyFQName)
            ?? ensureSyntheticPlatformEnumClass(
                named: "OsFamily",
                entries: [
                    "UNKNOWN", "MACOSX", "IOS", "LINUX", "WINDOWS",
                    "ANDROID", "WASM", "TVOS", "WATCHOS",
                ],
                in: kotlinNativePkg,
                symbols: symbols,
                interner: interner
            )
        let osFamilyType = types.make(.classType(ClassType(
            classSymbol: osFamilySymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: osFamilySymbol,
            enumType: osFamilyType,
            symbols: symbols
        )

        let cpuArchitectureSymbol = ensureSyntheticPlatformEnumClass(
            named: "CpuArchitecture",
            entries: [
                "UNKNOWN", "X86", "X64", "ARM32",
                "ARM64", "MIPS32", "MIPSEL32", "WASM32",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let cpuArchitectureType = types.make(.classType(ClassType(
            classSymbol: cpuArchitectureSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: cpuArchitectureSymbol,
            enumType: cpuArchitectureType,
            symbols: symbols
        )
        let memoryModelSymbol = ensureSyntheticPlatformEnumClass(
            named: "MemoryModel",
            entries: [
                "STRICT", "RELAXED", "EXPERIMENTAL",
            ],
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let memoryModelType = types.make(.classType(ClassType(
            classSymbol: memoryModelSymbol,
            args: [],
            nullability: .nonNull
        )))
        setSyntheticPlatformEnumEntryTypes(
            enumSymbol: memoryModelSymbol,
            enumType: memoryModelType,
            symbols: symbols
        )

        let platformSymbol = ensureSyntheticObjectSymbol(
            named: "Platform",
            in: kotlinNativePkg,
            symbols: symbols,
            interner: interner
        )
        let platformType = types.make(.classType(ClassType(
            classSymbol: platformSymbol,
            args: [],
            nullability: .nonNull
        )))
        let booleanType = types.make(.primitive(.boolean, .nonNull))
        symbols.setPropertyType(platformType, for: platformSymbol)

        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "canAccessUnaligned",
            propertyType: booleanType,
            externalLinkName: "kk_platform_canAccessUnaligned",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "isLittleEndian",
            propertyType: booleanType,
            externalLinkName: "kk_platform_isLittleEndian",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "osFamily",
            propertyType: osFamilyType,
            externalLinkName: "kk_platform_osFamily",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "cpuArchitecture",
            propertyType: cpuArchitectureType,
            externalLinkName: "kk_platform_cpuArchitecture",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: platformSymbol,
            name: "memoryModel",
            propertyType: memoryModelType,
            externalLinkName: "kk_platform_memoryModel",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: platformSymbol,
            ownerType: platformType,
            name: "getAvailableProcessors",
            externalLinkName: "kk_platform_getAvailableProcessors",
            returnType: types.intType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // --- java.lang.System / Runtime memory management (STDLIB-PERF-154) ---
        let javaLangPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("java"), interner.intern("lang")],
            symbols: symbols
        )
        let javaClassSymbol = ensureSyntheticJavaLangClassSymbol(
            in: javaLangPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticJavaClassExtensionProperty(
            kotlinPkg: kotlinPkg,
            javaClassSymbol: javaClassSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let javaSystemSymbol = ensureSyntheticObjectSymbol(
            named: "System",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        let javaSystemType = types.make(.classType(ClassType(
            classSymbol: javaSystemSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaSystemType, for: javaSystemSymbol)
        registerSyntheticSystemMember(
            ownerSymbol: javaSystemSymbol,
            ownerType: javaSystemType,
            name: "gc",
            externalLinkName: "kk_system_gc",
            returnType: types.unitType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        let runtimeSymbol = ensureSyntheticObjectSymbol(
            named: "Runtime",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        let runtimeType = types.make(.classType(ClassType(
            classSymbol: runtimeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(runtimeType, for: runtimeSymbol)
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "getRuntime",
            externalLinkName: "kk_runtime_getRuntime",
            returnType: runtimeType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "totalMemory",
            externalLinkName: "kk_runtime_totalMemory",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "freeMemory",
            externalLinkName: "kk_runtime_freeMemory",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSystemMember(
            ownerSymbol: runtimeSymbol,
            ownerType: runtimeType,
            name: "maxMemory",
            externalLinkName: "kk_runtime_maxMemory",
            returnType: types.longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // KSP-618: kotlin.synchronized is Kotlin source
        // (Stdlib/kotlin/Synchronized.kt) over the demoted __kk_synchronized
        // bridge, so no synthetic stub is registered here.

        registerSyntheticFileIOBootstrap(
            kotlinIOPkg: kotlinIOPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        // measureTime / measureTimedValue live in bundled Kotlin source
        // (Stdlib/kotlin/time/MeasureTime.kt).

        // --- STDLIB-HOF-029: 関数型完全実装 ---
        registerSyntheticFunctionTypes(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerSequenceScopeMember(
        named name: String,
        sequenceScopeSymbol: SymbolID,
        sequenceScopeFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = sequenceScopeFQName + [memberName]
        let parameterTypes = parameters.map(\.type)
        if symbols.lookupAll(fqName: memberFQName).contains(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == parameterTypes
        }) {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(sequenceScopeSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    func registerSequenceMemberStub(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        sequenceSymbol: SymbolID,
        sequenceFQName: [InternedString],
        typeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner,
        annotations: [MetadataAnnotationRecord] = [],
        canThrow: Bool = false,
        typeParameterUpperBounds: [TypeID] = [],
        typeParameterUpperBoundsList: [[TypeID]]? = nil,
        additionalTypeParameterSymbols: [SymbolID] = [],
        additionalTypeParameterUpperBoundsList: [[TypeID]] = [],
        flags: SymbolFlags = [.synthetic, .operatorFunction]
    ) {
        if BundledSyntheticStubRegistration.preBundledPass {
            return
        }

        let memberName = interner.intern(name)
        let memberFQName = sequenceFQName + [memberName]
        let requestedParameterTypes = parameters.map(\.type)
        let resolvedExternalLinkName = StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
            ownerKind: .sequence,
            memberName: name,
            arity: parameters.count,
            fallback: externalLinkName
        )

        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == requestedParameterTypes
                && signature.returnType == returnType
        }) {
            // KSP-441〜447: source Sequence 関数が存在すれば、合成外部リンクで上書きしない。
            if symbols.symbol(existing)?.declSite != nil {
                return
            }
            symbols.setExternalLinkName(resolvedExternalLinkName, for: existing)
            return
        }

        if let types = BundledSyntheticStubRegistration.types,
           BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: sequenceFQName,
               receiverType: receiverType,
               name: memberName,
               arity: parameters.count,
               symbols: symbols,
               types: types,
               interner: interner
           )
        {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(resolvedExternalLinkName, for: memberSymbol)
        if !annotations.isEmpty {
            symbols.setAnnotations(annotations, for: memberSymbol)
        }

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
        }

        let allTypeParameterSymbols = [typeParamSymbol] + additionalTypeParameterSymbols
        let reifiedTypeParameterIndices = Set(
            allTypeParameterSymbols.enumerated().compactMap { index, symbolID in
                symbols.symbol(symbolID)?.flags.contains(.reifiedTypeParameter) == true ? index : nil
            }
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                canThrow: canThrow,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: allTypeParameterSymbols,
                reifiedTypeParameterIndices: reifiedTypeParameterIndices,
                typeParameterUpperBoundsList: (typeParameterUpperBoundsList ?? [typeParameterUpperBounds]) + additionalTypeParameterUpperBoundsList,
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    func makeSyntheticIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableSymbol = symbols.lookup(fqName: iterableFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(propertyType, for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }

    private func ensureSyntheticJavaLangClassSymbol(
        in javaLangPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let classSymbol = ensureClassSymbol(
            named: "Class",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        let className = interner.intern("Class")
        let typeParamName = interner.intern("T")
        let typeParamFQName = javaLangPkg + [className, typeParamName]
        let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        return classSymbol
    }

    private func registerSyntheticJavaClassExtensionProperty(
        kotlinPkg: [InternedString],
        javaClassSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let propertyName = interner.intern("javaClass")
        let propertyFQName = kotlinPkg + [propertyName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = propertyFQName + [typeParamName]
        let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: javaClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let externalLinkName = "kk_any_javaClass"

        let propertySymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == typeParamType
        }) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: propertyName,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(packageSymbol, for: propertySymbol)
            }
            symbols.setExtensionPropertyReceiverType(typeParamType, for: propertySymbol)
        }

        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)

        let getterSymbol: SymbolID
        if let existingGetter = symbols.extensionPropertyGetterAccessor(for: propertySymbol) {
            getterSymbol = existingGetter
        } else {
            getterSymbol = symbols.define(
                kind: .function,
                name: interner.intern("get"),
                fqName: propertyFQName + [interner.intern("$get")],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(propertySymbol, for: getterSymbol)
            symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
            symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: typeParamType,
                parameterTypes: [],
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[types.anyType]],
                classTypeParameterCount: 0
            ),
            for: getterSymbol
        )
        symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
    }

    private func ensureSyntheticPlatformEnumClass(
        named name: String,
        entries: [String],
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: fqName) {
            enumSymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .enumClass,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
                symbols.setParentSymbol(pkgSymbol, for: symbol)
            }
            enumSymbol = symbol
        }

        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        return enumSymbol
    }

    private func setSyntheticPlatformEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        for child in symbols.children(ofFQName: enumInfo.fqName) {
            guard let childInfo = symbols.symbol(child), childInfo.kind == .field else {
                continue
            }
            symbols.setPropertyType(enumType, for: child)
        }
    }

}
