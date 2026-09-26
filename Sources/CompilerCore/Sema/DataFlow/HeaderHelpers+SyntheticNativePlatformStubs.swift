import RuntimeABI

/// Synthetic fallback registrations for the Kotlin/Native platform surface.
///
/// The historical TODO/IO bucket was split by responsibility in KUU-587.
/// Public TODO/console APIs are bundled Kotlin source; this file is the
/// compiler-only fallback for source-backed Native declarations plus the
/// synthetic MemoryModel enum surface.
extension DataFlowSemaPhase {
    func registerSyntheticNativePlatformStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty
    ) {
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

        // KSP-1198: use the bundled declaration when available so bitness,
        // enum entry order, and generated enum APIs follow the source contract.
        let cpuArchitectureFQName = kotlinNativePkg + [interner.intern("CpuArchitecture")]
        let cpuArchitectureSymbol = symbols.lookup(fqName: cpuArchitectureFQName)
            ?? ensureSyntheticPlatformEnumClass(
                named: "CpuArchitecture",
                entries: [
                    "UNKNOWN", "ARM32", "ARM64", "X86",
                    "X64", "MIPS32", "MIPSEL32", "WASM32",
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
        let memoryModelFQName = kotlinNativePkg + [interner.intern("MemoryModel")]
        let memoryModelSymbol = symbols.lookup(fqName: memoryModelFQName)
            ?? ensureSyntheticPlatformEnumClass(
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

        // KSP-1211: Platform's public surface is source-backed. The synthetic
        // registration pass runs before bundled headers are collected, so use
        // the declaration index rather than the symbol table to keep the
        // source-backed object and its members authoritative.
        let platformFQName = kotlinNativePkg + [interner.intern("Platform")]
        let hasSourceBackedPlatform = bundledIndex.contains(
            ownerFQName: platformFQName,
            name: interner.intern("canAccessUnaligned"),
            arity: 0
        )
        if !hasSourceBackedPlatform {
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
            registerSyntheticPlatformObjectProperty(
                ownerSymbol: platformSymbol,
                name: "canAccessUnaligned",
                propertyType: booleanType,
                externalLinkName: "kk_platform_canAccessUnaligned",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticPlatformObjectProperty(
                ownerSymbol: platformSymbol,
                name: "isLittleEndian",
                propertyType: booleanType,
                externalLinkName: "kk_platform_isLittleEndian",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticPlatformObjectProperty(
                ownerSymbol: platformSymbol,
                name: "osFamily",
                propertyType: osFamilyType,
                externalLinkName: "kk_platform_osFamily",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticPlatformObjectProperty(
                ownerSymbol: platformSymbol,
                name: "cpuArchitecture",
                propertyType: cpuArchitectureType,
                externalLinkName: "kk_platform_cpuArchitecture",
                symbols: symbols,
                interner: interner
            )
            registerSyntheticPlatformObjectProperty(
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
        }

    }

    private func registerSyntheticPlatformObjectProperty(
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

    /// Registers the generated enum APIs for the synthetic Native MemoryModel.
    /// The generic enum lowering pass reuses these symbols when it emits the
    /// values(), entries, and valueOf() bodies for the nominal enum owner.
    func registerSyntheticMemoryModelEnumMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let memoryModelFQName = [
            interner.intern("kotlin"),
            interner.intern("native"),
            interner.intern("MemoryModel"),
        ]
        // KSP-1191: Platform.kt owns the enum declaration and the compiler's
        // normal enum header pass synthesizes its generated members.
        guard !BundledSyntheticStubRegistration.bundledIndex.containsNominal(
            fqName: memoryModelFQName
        ) else {
            return
        }
        guard let enumSymbol = symbols.lookup(fqName: memoryModelFQName),
              let enumInfo = symbols.symbol(enumSymbol)
        else {
            return
        }
        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.experimental.ExperimentalNativeApi"
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"The only possible value returned in runtime is MemoryModel.EXPERIMENTAL now. The usages of this enum can be safely removed.\"",
                ]
            ),
        ]
        var existingAnnotations = symbols.annotations(for: enumSymbol)
        for annotation in annotations where !existingAnnotations.contains(annotation) {
            existingAnnotations.append(annotation)
        }
        symbols.setAnnotations(existingAnnotations, for: enumSymbol)

        let valuesName = interner.intern("values")
        let valuesFQName = enumInfo.fqName + [valuesName]
        let arrayFQName = [interner.intern("kotlin"), interner.intern("Array")]
        if let arraySymbol = symbols.lookup(fqName: arrayFQName),
           symbols.lookupAll(fqName: valuesFQName).allSatisfy({ symbols.symbol($0)?.kind != .function })
        {
            let arrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            let valuesSymbol = symbols.define(
                kind: .function,
                name: valuesName,
                fqName: valuesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(enumSymbol, for: valuesSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [],
                    returnType: arrayType,
                    isSuspend: false
                ),
                for: valuesSymbol
            )
        }

        let valueOfName = interner.intern("valueOf")
        let valueOfFQName = enumInfo.fqName + [valueOfName]
        if symbols.lookupAll(fqName: valueOfFQName).allSatisfy({ symbols.symbol($0)?.kind != .function }) {
            let parameterName = interner.intern("value")
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: valueOfFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let valueOfSymbol = symbols.define(
                kind: .function,
                name: valueOfName,
                fqName: valueOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(enumSymbol, for: valueOfSymbol)
            symbols.setParentSymbol(valueOfSymbol, for: parameterSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: [types.stringType],
                    returnType: enumType,
                    isSuspend: false,
                    valueParameterSymbols: [parameterSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false]
                ),
                for: valueOfSymbol
            )
        }

        let enumEntriesFQName = [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ]
        let entriesName = interner.intern("entries")
        let entriesFQName = enumInfo.fqName + [entriesName]
        if let enumEntriesSymbol = symbols.lookup(fqName: enumEntriesFQName),
           symbols.lookupAll(fqName: entriesFQName).allSatisfy({ symbols.symbol($0)?.kind != .property })
        {
            let entriesType = types.make(.classType(ClassType(
                classSymbol: enumEntriesSymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            let entriesSymbol = symbols.define(
                kind: .property,
                name: entriesName,
                fqName: entriesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(enumSymbol, for: entriesSymbol)
            symbols.setPropertyType(entriesType, for: entriesSymbol)
        }
    }

}
