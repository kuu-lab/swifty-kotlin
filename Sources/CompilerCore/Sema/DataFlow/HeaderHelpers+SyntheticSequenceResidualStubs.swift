import RuntimeABI

/// Synthetic stubs for residual `Sequence` member operations (`random`, `randomOrNull`,
/// `firstNotNullOf`, `firstNotNullOfOrNull`, `takeLast`,
/// `takeLastWhile`, and `reversed`) that are not yet migrated
/// to bundled Kotlin source.
///
/// KSP-694: Consolidated residual Sequence stubs after KSP-441..446 and KSP-308
/// migrations of terminal/HOF Sequence APIs to bundled Kotlin source.
/// KSP-1356: `shuffled`/`shuffled(random)` migrated out of this file onto
/// bundled Kotlin source (`SequenceConversionsAndSetOps.kt`); the
/// `kk_sequence_shuffled`/`kk_sequence_shuffled_random` runtime bridges stay,
/// now referenced via `@KsSymbolName` instead of a synthetic registration.
extension DataFlowSemaPhase {
    func registerSyntheticSequenceResidualMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
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

        let receiverType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let predicateType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))

        func nominalCollectionType(_ fqName: [InternedString], elementType: TypeID, invariant: Bool = false) -> TypeID {
            guard let symbol = symbols.lookup(fqName: fqName) else {
                return types.anyType
            }
            return types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [invariant ? .invariant(elementType) : .out(elementType)],
                nullability: .nonNull
            )))
        }

        let listReturnType = nominalCollectionType([
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ], elementType: typeParamType)

        // random(): T
        registerSequenceMemberStub(
            named: "random",
            externalLinkName: "kk_sequence_random",
            receiverType: receiverType,
            parameters: [],
            returnType: typeParamType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // randomOrNull(): T?
        registerSequenceMemberStub(
            named: "randomOrNull",
            externalLinkName: "kk_sequence_randomOrNull",
            receiverType: receiverType,
            parameters: [],
            returnType: types.makeNullable(typeParamType),
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // firstNotNullOf<T, R>(transform: (T) -> R?): R
        // Use a method-local T parameter (independent of Sequence's `out T`)
        // so the projection on the receiver does not block referencing T in
        // the transform's `in` position.
        do {
            let memberName = interner.intern("firstNotNullOf")
            let methodTName = interner.intern("T")
            let methodTSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, methodTName]) ?? symbols.define(
                kind: .typeParameter,
                name: methodTName,
                fqName: sequenceFQName + [memberName, methodTName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let methodTType = types.make(.typeParam(TypeParamType(symbol: methodTSymbol, nullability: .nonNull)))
            let methodReceiverType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(methodTType)],
                nullability: .nonNull
            )))
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: sequenceFQName + [memberName, rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let nullableRType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))
            let transformType = types.make(.functionType(FunctionType(
                params: [methodTType],
                returnType: nullableRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "firstNotNullOf",
                externalLinkName: "kk_sequence_firstNotNullOf",
                receiverType: methodReceiverType,
                parameters: [("transform", transformType)],
                returnType: rType,
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: methodTSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]],
                flags: [.synthetic, .inlineFunction]
            )
        }

        // firstNotNullOfOrNull<T, R>(transform: (T) -> R?): R?
        do {
            let memberName = interner.intern("firstNotNullOfOrNull")
            let methodTName = interner.intern("T")
            let methodTSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, methodTName]) ?? symbols.define(
                kind: .typeParameter,
                name: methodTName,
                fqName: sequenceFQName + [memberName, methodTName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let methodTType = types.make(.typeParam(TypeParamType(symbol: methodTSymbol, nullability: .nonNull)))
            let methodReceiverType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(methodTType)],
                nullability: .nonNull
            )))
            let rName = interner.intern("R")
            let rSymbol = symbols.lookup(fqName: sequenceFQName + [memberName, rName]) ?? symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: sequenceFQName + [memberName, rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let nullableRType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))
            let transformType = types.make(.functionType(FunctionType(
                params: [methodTType],
                returnType: nullableRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerSequenceMemberStub(
                named: "firstNotNullOfOrNull",
                externalLinkName: "kk_sequence_firstNotNullOfOrNull",
                receiverType: methodReceiverType,
                parameters: [("transform", transformType)],
                returnType: types.makeNullable(rType),
                sequenceSymbol: sequenceSymbol,
                sequenceFQName: sequenceFQName,
                typeParamSymbol: methodTSymbol,
                symbols: symbols,
                interner: interner,
                canThrow: true,
                additionalTypeParameterSymbols: [rSymbol],
                additionalTypeParameterUpperBoundsList: [[]],
                flags: [.synthetic, .inlineFunction]
            )
        }

        // takeLast(n: Int): List<T> (STDLIB-SEQ-FN-120)
        registerSequenceMemberStub(
            named: "takeLast",
            externalLinkName: "kk_sequence_takeLast",
            receiverType: receiverType,
            parameters: [("n", types.intType)],
            returnType: listReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
        )

        // takeLastWhile(predicate: (T) -> Boolean): List<T> (STDLIB-SEQ-FN-121)
        registerSequenceMemberStub(
            named: "takeLastWhile",
            externalLinkName: "kk_sequence_takeLastWhile",
            receiverType: receiverType,
            parameters: [("predicate", predicateType)],
            returnType: listReturnType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )

        // reversed(): Sequence<T> (STDLIB-SEQ-FN-099)
        registerSequenceMemberStub(
            named: "reversed",
            externalLinkName: "kk_sequence_reversed",
            receiverType: receiverType,
            parameters: [],
            returnType: receiverType,
            sequenceSymbol: sequenceSymbol,
            sequenceFQName: sequenceFQName,
            typeParamSymbol: typeParamSymbol,
            symbols: symbols,
            interner: interner
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
}
