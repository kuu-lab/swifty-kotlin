extension DataFlowSemaPhase {
    func registerSyntheticStringExtensionFunction(
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
        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: packageFQName,
            parentSymbol: symbols.lookup(fqName: packageFQName),
            receiverType: receiverType,
            parameters: parameters,
            returnType: returnType,
            externalLinkName: externalLinkName,
            annotations: annotations,
            flags: flags,
            symbols: symbols,
            interner: interner
        )
    }

    func registerAppendableMemberFunction(
        named name: String,
        externalLinkName: String,
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
        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: ownerInfo.fqName,
            parentSymbol: ownerSymbol,
            receiverType: ownerType,
            parameters: parameters,
            returnType: returnType,
            externalLinkName: externalLinkName,
            symbols: symbols,
            interner: interner
        )
    }

    var typographyCharConstants: [(name: String, scalar: UInt32)] {
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

    func registerTypographyCharConstant(
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

    func registerSyntheticStringTopLevelProperty(
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

    func registerSyntheticBigNumberMemberFunction(
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
        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: ownerInfo.fqName,
            parentSymbol: ownerSymbol,
            receiverType: ownerType,
            parameters: [],
            returnType: returnType,
            externalLinkName: externalLinkName,
            symbols: symbols,
            interner: interner
        )
    }

    func registerStringConstructorFromBytes(
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

    func ensureStringCompanionSymbol(
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

    func registerStringCompanionMethod(
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

        let varargFlags = isVararg.count == parameters.count
            ? isVararg
            : Array(repeating: false, count: parameters.count)

        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: companionFQName,
            parentSymbol: companionSymbol,
            parameters: syntheticFunctionParameters(
                parameters,
                hasDefaultValues: Array(repeating: false, count: parameters.count),
                isVararg: varargFlags
            ),
            returnType: returnType,
            externalLinkName: externalLinkName,
            matchReturnType: true,
            symbols: symbols,
            interner: interner
        )
    }
}
