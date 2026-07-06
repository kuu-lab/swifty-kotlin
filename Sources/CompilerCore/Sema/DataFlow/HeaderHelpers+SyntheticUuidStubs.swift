
/// Synthetic stdlib stubs for kotlin.uuid bridge-only extensions.
///
/// KSP-310: The public Uuid class API now lives in Stdlib/kotlin/uuid/Uuid.kt.
/// This file only keeps runtime-linked extensions that are still native-backed.
extension DataFlowSemaPhase {
    func registerSyntheticUuidStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinUuidPkg = ensureUuidPackageHierarchy(
            symbols: symbols,
            interner: interner
        )

        // --- Uuid class symbol ---
        let uuidSymbol = ensureClassSymbol(
            named: "Uuid",
            in: kotlinUuidPkg,
            symbols: symbols,
            interner: interner
        )
        attachExperimentalUuidApiAnnotation(to: uuidSymbol, symbols: symbols)

        let uuidType = types.make(.classType(ClassType(
            classSymbol: uuidSymbol,
            args: [],
            nullability: .nonNull
        )))
        // Resolve ByteArray for the remaining extension functions.
        let byteArrayFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("ByteArray")]
        let byteArrayType: TypeID
        if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            byteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        } else {
            byteArrayType = types.intType
        }

        // --- java.util.UUID.toKotlinUuid() extension ---
        // java.util.UUID.toKotlinUuid still uses a native bridge while java UUID
        // interop remains outside the Kotlinized Uuid class surface.
        let javaUuidType = registerJavaUuidType(symbols: symbols, types: types, interner: interner)
        registerToKotlinUuidExtension(
            javaUuidType: javaUuidType,
            uuidType: uuidType,
            kotlinUuidPkg: kotlinUuidPkg,
            symbols: symbols,
            interner: interner
        )

        // --- ByteArray extension functions in kotlin.uuid ---

        // ByteArray.putUuid(at: Int, uuid: Uuid): Unit
        registerUuidExtensionFunction(
            named: "putUuid",
            externalLinkName: "kk_byteArray_putUuid",
            receiverType: byteArrayType,
            parameters: [
                (name: "at", type: types.intType),
                (name: "uuid", type: uuidType),
            ],
            returnType: types.unitType,
            packageFQName: kotlinUuidPkg,
            symbols: symbols,
            interner: interner
        )

        // ByteArray.uuid(at: Int): Uuid
        registerUuidExtensionFunction(
            named: "uuid",
            externalLinkName: "kk_byteArray_uuid",
            receiverType: byteArrayType,
            parameters: [
                (name: "at", type: types.intType),
            ],
            returnType: uuidType,
            packageFQName: kotlinUuidPkg,
            symbols: symbols,
            interner: interner
        )

        // --- ByteArray.getUuid(offset: Int) extension in kotlin.uuid ---
        registerUuidTopLevelExtension(
            named: "getUuid",
            receiverType: byteArrayType,
            parameters: [(name: "offset", type: types.intType)],
            returnType: uuidType,
            externalLinkName: "kk_uuid_getUuid",
            packageFQName: kotlinUuidPkg,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureUuidPackageHierarchy(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let kotlinName = interner.intern("kotlin")
        let uuidName = interner.intern("uuid")
        let kotlinFQ: [InternedString] = [kotlinName]
        if symbols.lookup(fqName: kotlinFQ) == nil {
            _ = symbols.define(
                kind: .package, name: kotlinName, fqName: kotlinFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinUuidFQ: [InternedString] = [kotlinName, uuidName]
        if symbols.lookup(fqName: kotlinUuidFQ) == nil {
            _ = symbols.define(
                kind: .package, name: uuidName, fqName: kotlinUuidFQ,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        return kotlinUuidFQ
    }

    private func ensureUuidCompanionSymbol(
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

    private func registerUuidCompanionMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        companionFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = companionFQName + [memberName]
        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) {
            attachExperimentalUuidApiAnnotation(to: existing, symbols: symbols)
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
        attachExperimentalUuidApiAnnotation(to: memberSymbol, symbols: symbols)

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

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerUuidInstanceMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) {
            attachExperimentalUuidApiAnnotation(to: existing, symbols: symbols)
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
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        attachExperimentalUuidApiAnnotation(to: memberSymbol, symbols: symbols)

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

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerUuidInstanceProperty(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: {
            symbols.symbol($0)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            attachExperimentalUuidApiAnnotation(to: existing, symbols: symbols)
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
        attachExperimentalUuidApiAnnotation(to: propertySymbol, symbols: symbols)
    }

    private func registerUuidCompanionProperty(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: {
            symbols.symbol($0)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            symbols.insertFlags([.synthetic, .static], for: existing)
            attachExperimentalUuidApiAnnotation(to: existing, symbols: symbols)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
        attachExperimentalUuidApiAnnotation(to: propertySymbol, symbols: symbols)
    }

    private func registerUuidCompanionIntConstant(
        named name: String,
        value: Int64,
        ownerSymbol: SymbolID,
        intType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: {
            symbols.symbol($0)?.kind == .property
        }) {
            symbols.setPropertyType(intType, for: existing)
            symbols.setConstValueExprKind(.intLiteral(value), for: existing)
            symbols.insertFlags([.synthetic, .static, .constValue], for: existing)
            attachExperimentalUuidApiAnnotation(to: existing, symbols: symbols)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static, .constValue]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(intType, for: propertySymbol)
        symbols.setConstValueExprKind(.intLiteral(value), for: propertySymbol)
        attachExperimentalUuidApiAnnotation(to: propertySymbol, symbols: symbols)
    }

    private func registerJavaUuidType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let javaUtilPkg = ensurePackage(path: ["java", "util"], symbols: symbols, interner: interner)
        let javaUuidSymbol = ensureClassSymbol(
            named: "UUID",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol = symbols.lookup(fqName: javaUtilPkg) {
            symbols.setParentSymbol(pkgSymbol, for: javaUuidSymbol)
        }
        return types.make(.classType(ClassType(
            classSymbol: javaUuidSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func registerToKotlinUuidExtension(
        javaUuidType: TypeID,
        uuidType: TypeID,
        kotlinUuidPkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern("toKotlinUuid")
        let functionFQName = kotlinUuidPkg + [functionName]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == javaUuidType && sig.returnType == uuidType
        }) {
            attachExperimentalUuidApiAnnotation(to: existing, symbols: symbols)
            return
        }

        let pkgSymbol = symbols.lookup(fqName: kotlinUuidPkg)
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
        symbols.setExternalLinkName("kk_uuid_toKotlinUuid", for: functionSymbol)
        attachExperimentalUuidApiAnnotation(to: functionSymbol, symbols: symbols)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: javaUuidType,
                parameterTypes: [],
                returnType: uuidType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }

    private func registerUuidExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
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
            attachExperimentalUuidApiAnnotation(to: existing, symbols: symbols)
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
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        attachExperimentalUuidApiAnnotation(to: functionSymbol, symbols: symbols)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerUuidTopLevelExtension(
        named name: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let fnName = interner.intern(name)
        let fnFQName = packageFQName + [fnName]
        let paramTypes = parameters.map(\.type)

        if let existing = symbols.lookupAll(fqName: fnFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == receiverType
                && sig.parameterTypes == paramTypes
                && sig.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            attachExperimentalUuidApiAnnotation(to: existing, symbols: symbols)
            return
        }

        let fnSymbol = symbols.define(
            kind: .function,
            name: fnName,
            fqName: fnFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .throwingFunction]
        )
        if let pkgSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSymbol, for: fnSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: fnSymbol)
        attachExperimentalUuidApiAnnotation(to: fnSymbol, symbols: symbols)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: fnFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(fnSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: paramTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: fnSymbol
        )
    }

    private func attachExperimentalUuidApiAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(annotationFQName: "kotlin.uuid.ExperimentalUuidApi")
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(record) {
            annotations.append(record)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
