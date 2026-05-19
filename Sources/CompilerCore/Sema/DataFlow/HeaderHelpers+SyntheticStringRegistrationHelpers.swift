/// Shared helpers for synthetic kotlin.text String stub registration.
///
/// Kept outside the main stub registration file so the surface list stays easier to scan.
enum SyntheticStringStubRegistration {
    static func ensureKotlinTextPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
        if symbols.lookup(fqName: kotlinTextPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("text"),
                fqName: kotlinTextPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return kotlinTextPkg
    }

    static func makeListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listSymbol = ensureListSymbol(symbols: symbols, types: types, interner: interner)
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    static func makeSequenceType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let sequenceSymbol = ensureSequenceSymbol(
            symbols: symbols, types: types, interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    static func ensureSequenceSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let sequenceName = interner.intern("Sequence")
        let sequenceFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            sequenceName,
        ]
        if let existing = symbols.lookup(fqName: sequenceFQName) {
            return existing
        }
        // Ensure the kotlin.sequences package exists
        let sequencesPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
        ]
        if symbols.lookup(fqName: sequencesPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("sequences"),
                fqName: sequencesPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let sym = symbols.define(
            kind: .interface,
            name: sequenceName,
            fqName: sequenceFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        // Register type parameter T for Sequence<T>
        let typeParamName = interner.intern("T")
        let typeParamFQName = sequenceFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sym)
        types.setNominalTypeParameterVariances([.out], for: sym)
        return sym
    }

    static func makeIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableSymbol = ensureIterableSymbol(
            symbols: symbols, types: types, interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    static func makeCollectionType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let collectionSymbol = ensureCollectionSymbol(
            symbols: symbols,
            types: types,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: collectionSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    static func ensureCollectionSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let collectionName = interner.intern("Collection")
        let collectionFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            collectionName,
        ]
        if let existing = symbols.lookup(fqName: collectionFQName) {
            return existing
        }
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        if symbols.lookup(fqName: collectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: collectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let sym = symbols.define(
            kind: .interface,
            name: collectionName,
            fqName: collectionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let typeParamName = interner.intern("E")
        let typeParamFQName = collectionFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sym)
        types.setNominalTypeParameterVariances([.out], for: sym)
        return sym
    }

    static func ensureIterableSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let iterableName = interner.intern("Iterable")
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            iterableName,
        ]
        if let existing = symbols.lookup(fqName: iterableFQName) {
            return existing
        }
        // Ensure the kotlin.collections package exists
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        if symbols.lookup(fqName: collectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: collectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let sym = symbols.define(
            kind: .interface,
            name: iterableName,
            fqName: iterableFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        // Register type parameter T for Iterable<T>
        let typeParamName = interner.intern("T")
        let typeParamFQName = iterableFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: sym)
        types.setNominalTypeParameterVariances([.out], for: sym)
        return sym
    }

    static func makeListOfStringType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        makeListType(symbols: symbols, types: types, interner: interner, elementType: types.stringType)
    }

    static func makeNominalType(
        symbols: SymbolTable,
        types: TypeSystem,
        fqName: [InternedString]
    ) -> TypeID {
        if let symbol = symbols.lookup(fqName: fqName) {
            return types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [],
                nullability: .nonNull
            )))
        }

        guard let name = fqName.last else {
            return types.anyType
        }

        var packagePath: [InternedString] = []
        for packageName in fqName.dropLast() {
            packagePath.append(packageName)
            if symbols.lookup(fqName: packagePath) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: packageName,
                    fqName: packagePath,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }

        let symbol = symbols.define(
            kind: .class,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    static func ensureListSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        if symbols.lookup(fqName: collectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: collectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let listName = interner.intern("List")
        let listFQName = collectionsPkg + [listName]
        if let existing = symbols.lookup(fqName: listFQName) {
            return existing
        }
        let interfaceSymbol = symbols.define(
            kind: .interface,
            name: listName,
            fqName: listFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let typeParamName = interner.intern("E")
        let typeParamFQName = listFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: interfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: interfaceSymbol)
        return interfaceSymbol
    }

    static func registerSyntheticStringExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        annotations: [MetadataAnnotationRecord] = [],
        flags: SymbolFlags = [.synthetic],
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if !annotations.isEmpty {
                symbols.setAnnotations(annotations, for: existing)
            }
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        if !annotations.isEmpty {
            symbols.setAnnotations(annotations, for: functionSymbol)
        }

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []
        parameterTypes.reserveCapacity(parameters.count)
        parameterSymbols.reserveCapacity(parameters.count)
        parameterDefaults.reserveCapacity(parameters.count)
        parameterVarargs.reserveCapacity(parameters.count)

        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
            parameterDefaults.append(parameter.hasDefault)
            parameterVarargs.append(parameter.isVararg)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: parameterVarargs,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
    }

    static func registerAppendableMemberFunction(
        named name: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) {
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
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []

        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
            parameterDefaults.append(parameter.hasDefault)
            parameterVarargs.append(parameter.isVararg)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: parameterVarargs,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
    }

    static var typographyCharConstants: [(name: String, scalar: UInt32)] {
        [
            ("almostEqual", 0x2248),
            ("amp", 0x0026),
            ("bullet", 0x2022),
            ("cent", 0x00A2),
            ("copyright", 0x00A9),
            ("dagger", 0x2020),
            ("degree", 0x00B0),
            ("dollar", 0x0024),
            ("doubleDagger", 0x2021),
            ("doublePrime", 0x2033),
            ("ellipsis", 0x2026),
            ("euro", 0x20AC),
            ("greater", 0x003E),
            ("greaterOrEqual", 0x2265),
            ("half", 0x00BD),
            ("leftDoubleQuote", 0x201C),
            ("leftGuillemet", 0x00AB),
            ("leftGuillemete", 0x00AB),
            ("leftSingleQuote", 0x2018),
            ("less", 0x003C),
            ("lessOrEqual", 0x2264),
            ("lowDoubleQuote", 0x201E),
            ("lowSingleQuote", 0x201A),
            ("mdash", 0x2014),
            ("middleDot", 0x00B7),
            ("nbsp", 0x00A0),
            ("ndash", 0x2013),
            ("notEqual", 0x2260),
            ("paragraph", 0x00B6),
            ("plusMinus", 0x00B1),
            ("pound", 0x00A3),
            ("prime", 0x2032),
            ("quote", 0x0022),
            ("registered", 0x00AE),
            ("rightDoubleQuote", 0x201D),
            ("rightGuillemet", 0x00BB),
            ("rightGuillemete", 0x00BB),
            ("rightSingleQuote", 0x2019),
            ("section", 0x00A7),
            ("times", 0x00D7),
            ("tm", 0x2122),
        ]
    }

    static func registerTypographyCharConstant(
        ownerSymbol: SymbolID,
        name: String,
        scalar: UInt32,
        charType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: {
            symbols.symbol($0)?.kind == .property
        }) {
            symbols.setPropertyType(charType, for: existing)
            symbols.setConstValueExprKind(.charLiteral(scalar), for: existing)
            symbols.insertFlags([.synthetic, .constValue], for: existing)
            return
        }
        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .constValue]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(charType, for: propertySymbol)
        symbols.setConstValueExprKind(.charLiteral(scalar), for: propertySymbol)
    }

    static func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        ownerType _: TypeID,
        name: String,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else {
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
    }

    static func registerSyntheticStringTopLevelProperty(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        externalLinkName: String,
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }

    static func registerSyntheticBigNumberMemberFunction(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).isEmpty else {
            return
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }

    static func registerStringConstructorFromBytes(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    // MARK: - String Companion Helpers

    static func ensureStringCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if let existingCompanion = symbols.companionObjectSymbol(for: ownerSymbol),
           let companionInfo = symbols.symbol(existingCompanion)
        {
            return companionInfo.fqName
        }

        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return []
        }
        let companionName = interner.intern("Companion")
        let companionFQName = ownerInfo.fqName + [companionName]
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
        return companionFQName
    }

    static func registerStringCompanionMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        isVararg: [Bool],
        companionFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = companionFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) == nil else {
            return
        }

        guard let companionSymbol = symbols.lookup(fqName: companionFQName) else {
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
        symbols.setParentSymbol(companionSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        let hasDefaults = Array(repeating: false, count: parameters.count)
        let varargFlags = isVararg.count == parameters.count
            ? isVararg
            : Array(repeating: false, count: parameters.count)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: hasDefaults,
                valueParameterIsVararg: varargFlags
            ),
            for: memberSymbol
        )
    }

    static func registerSyntheticLocaleConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }
}
