// swiftlint:disable file_length

private enum SyntheticAnnotationAPISurfaceForHelpers {
    static let targetEntries = [
        "CLASS", "ANNOTATION_CLASS", "TYPE_PARAMETER", "PROPERTY", "FIELD",
        "LOCAL_VARIABLE", "VALUE_PARAMETER", "CONSTRUCTOR", "FUNCTION",
        "PROPERTY_GETTER", "PROPERTY_SETTER", "TYPE", "EXPRESSION", "FILE",
        "TYPEALIAS",
    ]
    static let retentionEntries = ["SOURCE", "BINARY", "RUNTIME"]
}

/// AnnotationTarget / Retention / RequiresOptInLevel
/// enums, the throws-exception-classes property/constructor, and
/// generic String / Boolean / Int annotation property/constructor
/// registration helpers.
///
/// Split out from `HeaderHelpers+SyntheticMetaprogStubs.swift`.
extension DataFlowSemaPhase {
    func attachAnnotationIfNeeded(
        _ annotation: MetadataAnnotationRecord,
        to symbolFQName: [InternedString],
        symbols: SymbolTable
    ) {
        guard let symbol = symbols.lookup(fqName: symbolFQName) else {
            return
        }
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(annotation) {
            annotations.append(annotation)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }



    func registerSyntheticAnnotationTargetEnum(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let enumName = interner.intern("AnnotationTarget")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: enumSymbol)
            }
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in SyntheticAnnotationAPISurfaceForHelpers.targetEntries {
            let entry = interner.intern(entryName)
            let entryFQName = enumFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
        }
    }

    func registerSyntheticAnnotationRetentionEnum(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let enumName = interner.intern("AnnotationRetention")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: enumSymbol)
            }
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in SyntheticAnnotationAPISurfaceForHelpers.retentionEntries {
            let entry = interner.intern(entryName)
            let entryFQName = enumFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
        }
    }

    func registerSyntheticThrowsExceptionClassesPropertyAndConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        kotlinPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let exceptionClassesName = interner.intern("exceptionClasses")
        let exceptionClassesFQName = ownerFQName + [exceptionClassesName]
        let exceptionClassesSymbol: SymbolID
        if let existing = symbols.lookup(fqName: exceptionClassesFQName) {
            exceptionClassesSymbol = existing
        } else {
            exceptionClassesSymbol = symbols.define(
                kind: .property,
                name: exceptionClassesName,
                fqName: exceptionClassesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: exceptionClassesSymbol)

        let throwableType = makeSyntheticThrowsThrowableType(
            kotlinPkg: kotlinPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let exceptionKClassType = types.makeKClassType(argument: throwableType)
        let exceptionClassesType = makeSyntheticThrowsExceptionClassesArrayType(
            elementType: exceptionKClassType,
            kotlinPkg: kotlinPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        symbols.setPropertyType(exceptionClassesType, for: exceptionClassesSymbol)

        let initName = interner.intern("<init>")
        let constructorFQName = ownerFQName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [exceptionKClassType]
                && signature.valueParameterIsVararg == [true]
        }
        guard !hasMatchingConstructor else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)

        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: exceptionClassesName,
            fqName: constructorFQName + [exceptionClassesName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)

        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [exceptionKClassType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true]
            ),
            for: constructorSymbol
        )
    }


    func makeSyntheticThrowsThrowableType(
        kotlinPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let throwableFQName = kotlinPkg + [interner.intern("Throwable")]
        guard let throwableSymbol = symbols.lookup(fqName: throwableFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func makeSyntheticThrowsExceptionClassesArrayType(
        elementType: TypeID,
        kotlinPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let arrayFQName = kotlinPkg + [interner.intern("Array")]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func registerSyntheticStringAnnotationPropertyAndConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        propertyName: String,
        parameterHasDefaultValue: Bool = false,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let property = interner.intern(propertyName)
        let propertyFQName = ownerFQName + [property]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: property,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(types.stringType, for: propertySymbol)

        let initName = interner.intern("<init>")
        let constructorFQName = ownerFQName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [types.stringType]
        }
        guard !hasMatchingConstructor else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)

        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: property,
            fqName: constructorFQName + [property],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)

        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.stringType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [parameterHasDefaultValue],
                valueParameterIsVararg: [false]
            ),
            for: constructorSymbol
        )
    }

    func appendSyntheticAnnotation(
        _ annotation: MetadataAnnotationRecord,
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(annotation) {
            annotations.append(annotation)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
