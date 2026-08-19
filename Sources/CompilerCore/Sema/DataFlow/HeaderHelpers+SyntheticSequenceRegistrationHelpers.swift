// swiftlint:disable file_length

/// Synthetic `kotlin.sequences.Sequence` registration helpers:
/// stub registration, extension-function helpers, builder/iterator
/// builder, factory and generic-sequence helpers, and the
/// `joinTo` / `joinToString` member registration.
///
/// Split out from `HeaderHelpers+SyntheticTODOAndIOStubs.swift`.
extension DataFlowSemaPhase {
    func registerSyntheticSequenceJoinToMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinSequencesPkg: [InternedString],
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName = kotlinSequencesPkg + [sequenceName]
        let sequenceSymbol: SymbolID = if let existing = symbols.lookup(fqName: sequenceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: sequenceName,
                fqName: sequenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sequenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)

        let memberName = interner.intern("joinTo")
        let memberFQName = sequenceFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let kotlinTextPkg = ensurePackage(path: ["kotlin", "text"], symbols: symbols, interner: interner)
        let appendableSymbol = ensureInterfaceSymbol(
            named: "Appendable",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg) {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: appendableSymbol)
        }
        let appendableType = types.make(.classType(ClassType(
            classSymbol: appendableSymbol,
            args: [],
            nullability: .nonNull
        )))

        let parameters: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("buffer", appendableType, false),
            ("separator", types.stringType, true),
            ("prefix", types.stringType, true),
            ("postfix", types.stringType, true),
        ]

        // KSP-INF-011: Guard the default overload against bundled source.
        if BundledSyntheticStubRegistration.shouldSkipRegistration(
            declaredOwnerFQName: sequenceFQName,
            receiverType: receiverType,
            name: memberName,
            arity: parameters.count,
            symbols: symbols,
            types: types,
            interner: interner
        ) {
            skipStats?.recordSkip(ownerFQName: sequenceFQName, name: memberName, arity: parameters.count, interner: interner)
            return
        }

        registerSyntheticFunctionStub(
            named: "joinTo",
            ownerFQName: sequenceFQName,
            parentSymbol: sequenceSymbol,
            receiverType: receiverType,
            parameters: syntheticFunctionParameters(parameters),
            returnType: appendableType,
            externalLinkName: "",
            flags: [.synthetic, .operatorFunction],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticSequenceJoinToStringMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinSequencesPkg: [InternedString],
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName = kotlinSequencesPkg + [sequenceName]
        let sequenceSymbol: SymbolID = if let existing = symbols.lookup(fqName: sequenceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: sequenceName,
                fqName: sequenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sequenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)

        let memberName = interner.intern("joinToString")
        let memberFQName = sequenceFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let parameters: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("separator", types.stringType, true),
            ("prefix", types.stringType, true),
            ("postfix", types.stringType, true),
        ]

        // KSP-INF-011: Guard the default overload against bundled source.
        if BundledSyntheticStubRegistration.shouldSkipRegistration(
            declaredOwnerFQName: sequenceFQName,
            receiverType: receiverType,
            name: memberName,
            arity: parameters.count,
            symbols: symbols,
            types: types,
            interner: interner
        ) {
            skipStats?.recordSkip(ownerFQName: sequenceFQName, name: memberName, arity: parameters.count, interner: interner)
            return
        }

        registerSyntheticFunctionStub(
            named: "joinToString",
            ownerFQName: sequenceFQName,
            parentSymbol: sequenceSymbol,
            receiverType: receiverType,
            parameters: syntheticFunctionParameters(parameters),
            returnType: types.stringType,
            externalLinkName: "",
            flags: [.synthetic, .operatorFunction],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticSystemMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: ownerInfo.fqName,
            parentSymbol: ownerSymbol,
            receiverType: ownerType,
            parameters: syntheticFunctionParameters(parameters),
            returnType: returnType,
            externalLinkName: externalLinkName,
            matchReturnType: true,
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticIOTopLevelProperty(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        externalLinkName: String,
        constValue: KIRExprKind? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            if let constValue {
                symbols.insertFlags(.constValue, for: existing)
                symbols.setConstValueExprKind(constValue, for: existing)
            }
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: constValue == nil ? [.synthetic] : [.synthetic, .constValue]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
        if let constValue {
            symbols.setConstValueExprKind(constValue, for: propertySymbol)
        }
    }

    func registerSyntheticTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        annotations: [MetadataAnnotationRecord] = [],
        stdlibSpecialCallKind: StdlibSpecialCallKind? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionSymbol = registerSyntheticFunctionStub(
            named: name,
            ownerFQName: packageFQName,
            parentSymbol: symbols.lookup(fqName: packageFQName),
            parameters: syntheticFunctionParameters(parameters),
            returnType: returnType,
            externalLinkName: externalLinkName,
            annotations: annotations,
            matchReturnType: true,
            symbols: symbols,
            interner: interner
        )
        if let stdlibSpecialCallKind {
            symbols.setStdlibSpecialCallKind(stdlibSpecialCallKind, for: functionSymbol)
        }
    }


    func registerSyntheticSequenceStub(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName = packageFQName + [sequenceName]
        let sequenceSymbol: SymbolID = if let existing = symbols.lookup(fqName: sequenceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: sequenceName,
                fqName: sequenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sequenceSymbol)
        types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)

        let sequenceElementType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        // KSP-441〜447: source Sequence インターフェースがあれば iterator() は source 側で定義する。
        let bundledIndex = BundledSyntheticStubRegistration.bundledIndex
        let iteratorName = interner.intern("iterator")
        let hasSourceIterator = bundledIndex.contains(
            owner: sequenceFQName,
            name: iteratorName,
            arity: 0
        )
        if !hasSourceIterator {
            registerSyntheticSequenceIteratorMember(
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                elementType: sequenceElementType,
                typeParameterSymbol: typeParamSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        let nullableReceiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(sequenceElementType)],
            nullability: .nullable
        )))
        let nonNullReceiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(sequenceElementType)],
            nullability: .nonNull
        )))
        registerSyntheticSequenceExtensionFunction(
            named: "orEmpty",
            externalLinkName: "kk_sequence_orEmpty",
            receiverType: nullableReceiverType,
            parameters: [],
            returnType: nonNullReceiverType,
            typeParameterSymbols: [typeParamSymbol],
            packageFQName: packageFQName,
            symbols: symbols,
            interner: interner
        )

        return sequenceSymbol
    }

    /// Idempotent fallback for contexts without the bundled Sequence declaration.
    func ensureSyntheticSequenceStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        bundledIndex: BundledDeclarationIndex = .empty
    ) -> SymbolID {
        let kotlinSequencesPkg: [InternedString] = [
            interner.intern("kotlin"), interner.intern("sequences")
        ]
        if symbols.lookup(fqName: kotlinSequencesPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("sequences"),
                fqName: kotlinSequencesPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let sequenceName = interner.intern("Sequence")
        let sequenceFQName = kotlinSequencesPkg + [sequenceName]
        let sequenceSymbol: SymbolID = if let existing = symbols.lookup(fqName: sequenceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: sequenceName,
                fqName: sequenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let seqTypeParamName = interner.intern("T")
        let seqTypeParamFQName = sequenceFQName + [seqTypeParamName]
        if symbols.lookup(fqName: seqTypeParamFQName) == nil {
            let seqTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: seqTypeParamName,
                fqName: seqTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            types.setNominalTypeParameterSymbols([seqTypeParamSymbol], for: sequenceSymbol)
            types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)
        }

        // Register iterator() independently of the type parameter block above,
        // so it's added even when Sequence<T> was created elsewhere.
        let iterFnName = interner.intern("iterator")
        let iterFnFQName = sequenceFQName + [iterFnName]
        let hasSourceIterator = bundledIndex.contains(
            owner: sequenceFQName,
            name: iterFnName,
            arity: 0
        )
        if !hasSourceIterator, symbols.lookup(fqName: iterFnFQName) == nil {
            if let seqTypeParamSymbol = symbols.lookup(fqName: seqTypeParamFQName) {
                let seqTypeParamType = types.make(.typeParam(TypeParamType(
                    symbol: seqTypeParamSymbol, nullability: .nonNull
                )))
                let iteratorName = interner.intern("Iterator")
                let iteratorFQName = kotlinCollectionsPkg + [iteratorName]
                if let iteratorSymbol = symbols.lookup(fqName: iteratorFQName) {
                    let iteratorReturnType = types.make(.classType(ClassType(
                        classSymbol: iteratorSymbol,
                        args: [.out(seqTypeParamType)],
                        nullability: .nonNull
                    )))
                    let iterFnSymbol = symbols.define(
                        kind: .function,
                        name: iterFnName,
                        fqName: iterFnFQName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic, .operatorFunction]
                    )
                    symbols.setParentSymbol(sequenceSymbol, for: iterFnSymbol)
                    let seqReceiverType = types.make(.classType(ClassType(
                        classSymbol: sequenceSymbol,
                        args: [.out(seqTypeParamType)],
                        nullability: .nonNull
                    )))
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: seqReceiverType,
                            parameterTypes: [],
                            returnType: iteratorReturnType,
                            typeParameterSymbols: [seqTypeParamSymbol],
                            classTypeParameterCount: 1
                        ),
                        for: iterFnSymbol
                    )
                }
            }
        }

        return sequenceSymbol
    }

    private func registerSyntheticSequenceIteratorMember(
        sequenceSymbol: SymbolID,
        sequenceFQName: [InternedString],
        elementType: TypeID,
        typeParameterSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let iteratorSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterator"),
        ])
        guard let iteratorSymbol else { return }

        let iteratorReturnType = types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let memberName = interner.intern("iterator")
        let memberFQName = sequenceFQName + [memberName]
        let memberSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .function
        }) {
            memberSymbol = existing
        } else {
            memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(sequenceSymbol, for: memberSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: iteratorReturnType,
                typeParameterSymbols: [typeParameterSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    func registerSyntheticSequenceExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        typeParameterSymbols: [SymbolID] = [],
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: packageFQName,
            parentSymbol: symbols.lookup(fqName: packageFQName),
            receiverType: receiverType,
            parameters: parameters,
            returnType: returnType,
            externalLinkName: externalLinkName,
            typeParameterSymbols: typeParameterSymbols,
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticSequenceBuilderStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinSequencesPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("sequences")],
            symbols: symbols
        )
        let sequenceSymbol = registerSyntheticSequenceStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let scopeName = interner.intern("SequenceScope")
        let scopeFQName = kotlinSequencesPkg + [scopeName]
        let scopeSymbol: SymbolID
        if let existing = symbols.lookup(fqName: scopeFQName) {
            scopeSymbol = existing
        } else {
            let sym = symbols.define(
                kind: .class,
                name: scopeName,
                fqName: scopeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinSequencesPkg) {
                symbols.setParentSymbol(packageSymbol, for: sym)
            }
            scopeSymbol = sym
        }
        let scopeTypeParamName = interner.intern("T")
        let scopeTypeParamFQName = scopeFQName + [scopeTypeParamName]
        let scopeTypeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: scopeTypeParamFQName) {
            scopeTypeParamSymbol = existing
        } else {
            let param = symbols.define(
                kind: .typeParameter,
                name: scopeTypeParamName,
                fqName: scopeTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(scopeSymbol, for: param)
            scopeTypeParamSymbol = param
        }
        types.setNominalTypeParameterSymbols([scopeTypeParamSymbol], for: scopeSymbol)
        types.setNominalTypeParameterVariances([.in], for: scopeSymbol)

        let scopeTypeParamType = types.make(.typeParam(TypeParamType(symbol: scopeTypeParamSymbol)))
        let scopeReceiverType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(scopeTypeParamType)],
            nullability: .nonNull
        )))
        let iteratorType = nominalSequenceParameterType(
            package: ["kotlin", "collections", "Iterator"],
            elementType: scopeTypeParamType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let iterableType = nominalSequenceParameterType(
            package: ["kotlin", "collections", "Iterable"],
            elementType: scopeTypeParamType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let sequenceType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(scopeTypeParamType)],
            nullability: .nonNull
        )))
        registerSequenceScopeMember(
            named: "yield",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "value", type: scopeTypeParamType)],
            returnType: types.unitType,
            externalLinkName: "__kk_sequence_builder_yield",
            symbols: symbols,
            interner: interner
        )

        registerSequenceScopeMember(
            named: "yieldAll",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "iterator", type: iteratorType)],
            returnType: types.unitType,
            externalLinkName: "__kk_sequence_builder_yieldAll",
            symbols: symbols,
            interner: interner
        )
        registerSequenceScopeMember(
            named: "yieldAll",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "elements", type: iterableType)],
            returnType: types.unitType,
            externalLinkName: "__kk_sequence_builder_yieldAll",
            symbols: symbols,
            interner: interner
        )
        registerSequenceScopeMember(
            named: "yieldAll",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "sequence", type: sequenceType)],
            returnType: types.unitType,
            externalLinkName: "__kk_sequence_builder_yieldAll",
            symbols: symbols,
            interner: interner
        )

        let functionName = interner.intern("sequence")
        let functionFQName = kotlinSequencesPkg + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
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
        if let packageSymbol = symbols.lookup(fqName: kotlinSequencesPkg) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("__kk_sequence_builder_build", for: functionSymbol)

        let functionTypeParamName = interner.intern("T")
        let functionTypeParamFQName = functionFQName + [functionTypeParamName]
        let functionTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: functionTypeParamName,
            fqName: functionTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(functionSymbol, for: functionTypeParamSymbol)

        let builderTypeParamType = types.make(.typeParam(TypeParamType(symbol: functionTypeParamSymbol)))
        let sequenceReturnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(builderTypeParamType)],
            nullability: .nonNull
        )))
        let builderScopeType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(builderTypeParamType)],
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            receiver: builderScopeType,
            params: [],
            returnType: types.unitType,
            isSuspend: true
        )))

        let blockParamName = interner.intern("block")
        let blockParamSymbol = symbols.define(
            kind: .valueParameter,
            name: blockParamName,
            fqName: functionFQName + [blockParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: blockParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [blockType],
                returnType: sequenceReturnType,
                valueParameterSymbols: [blockParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [functionTypeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func nominalSequenceParameterType(
        package: [String],
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let fqName = package.map { interner.intern($0) }
        guard let symbol = symbols.lookup(fqName: fqName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    // STDLIB-331/564: iterator {} builder → Iterator<T>
    // Mirrors registerSyntheticSequenceBuilderStub but returns Iterator<T>
    // instead of Sequence<T>, and reuses the SequenceScope<T> receiver for yield().
    func registerSyntheticIteratorBuilderStub(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Reuse the SequenceScope class registered by sequence {} builder.
        let scopeName = interner.intern("SequenceScope")
        let scopeFQName = packageFQName + [scopeName]
        let scopeSymbol: SymbolID
        if let existing = symbols.lookup(fqName: scopeFQName) {
            scopeSymbol = existing
        } else {
            let sym = symbols.define(
                kind: .class,
                name: scopeName,
                fqName: scopeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName) {
                symbols.setParentSymbol(packageSymbol, for: sym)
            }
            scopeSymbol = sym
        }

        let functionName = interner.intern("iterator")
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
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
        symbols.setExternalLinkName("__kk_iterator_builder_build", for: functionSymbol)

        let functionTypeParamName = interner.intern("T")
        let functionTypeParamFQName = functionFQName + [functionTypeParamName]
        let functionTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: functionTypeParamName,
            fqName: functionTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(functionSymbol, for: functionTypeParamSymbol)

        let builderTypeParamType = types.make(.typeParam(TypeParamType(symbol: functionTypeParamSymbol)))

        // Return type: Iterator<T>
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        let iteratorInterfaceFQName = kotlinCollectionsPkg + [interner.intern("Iterator")]
        let iteratorReturnType: TypeID
        if let iteratorSymbol = symbols.lookup(fqName: iteratorInterfaceFQName) {
            iteratorReturnType = types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(builderTypeParamType)],
                nullability: .nonNull
            )))
        } else {
            iteratorReturnType = types.anyType
        }

        // Block type: SequenceScope<T>.() -> Unit  (with receiver so yield() resolves)
        let builderScopeType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(builderTypeParamType)],
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            receiver: builderScopeType,
            params: [],
            returnType: types.unitType,
            isSuspend: true
        )))

        let blockParamName = interner.intern("block")
        let blockParamSymbol = symbols.define(
            kind: .valueParameter,
            name: blockParamName,
            fqName: functionFQName + [blockParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: blockParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [blockType],
                returnType: iteratorReturnType,
                valueParameterSymbols: [blockParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [functionTypeParamSymbol]
            ),
            for: functionSymbol
        )
    }
}
