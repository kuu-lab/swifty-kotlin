extension DataFlowSemaPhase {
    func registerPathCopyActionContextSurface(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let contextSymbol = ensureInterfaceSymbol(
            named: "CopyActionContext",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: contextSymbol)
        }
        let contextType = types.make(.classType(ClassType(
            classSymbol: contextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(contextType, for: contextSymbol)
    }

    func registerPathExperimentalPathApiAnnotation(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "ExperimentalPathApi",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: annotationSymbol)
        }

        var annotations = symbols.annotations(for: annotationSymbol)
        let requiresOptIn = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: ["level=RequiresOptIn.Level.ERROR"]
        )
        if !annotations.contains(requiresOptIn) {
            annotations.append(requiresOptIn)
        }

        let target = MetadataAnnotationRecord(
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
        if !annotations.contains(target) {
            annotations.append(target)
        }
        symbols.setAnnotations(annotations, for: annotationSymbol)
    }

    func ensurePathCopyActionResultEnum(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("CopyActionResult")
        let fqName = packageFQName + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }

        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: enumSymbol)
        }

        for entry in ["CONTINUE", "SKIP_SUBTREE", "TERMINATE"] {
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

    func ensurePathOnErrorResultEnum(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("OnErrorResult")
        let fqName = packageFQName + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }

        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: enumSymbol)
        }

        for entry in ["SKIP_SUBTREE", "TERMINATE"] {
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

    func ensurePathWalkOptionEnum(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("PathWalkOption")
        let fqName = packageFQName + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }

        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: enumSymbol)
        }

        for entry in ["BREADTH_FIRST", "FOLLOW_LINKS"] {
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

    func setPathEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let children = symbols.children(ofFQName: enumInfo.fqName)
        for child in children {
            guard let childSym = symbols.symbol(child),
                  childSym.kind == .field
            else {
                continue
            }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }

    func registerPathFileVisitorBuilderSurface(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let builderSymbol = ensureInterfaceSymbol(
            named: "FileVisitorBuilder",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: builderSymbol)
        }
        let builderType = types.make(.classType(ClassType(
            classSymbol: builderSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(builderType, for: builderSymbol)
    }

    func ensureGenericPathFileVisitorSymbol(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let fileVisitorSymbol = ensureInterfaceSymbol(
            named: "FileVisitor",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: fileVisitorSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = packageFQName + [interner.intern("FileVisitor"), typeParamName]
        let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(fileVisitorSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: fileVisitorSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: fileVisitorSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let fileVisitorType = types.make(.classType(ClassType(
            classSymbol: fileVisitorSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(fileVisitorType, for: fileVisitorSymbol)
        return fileVisitorSymbol
    }

    func ensureGenericFileAttributeSymbol(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let fileAttributeSymbol = ensureInterfaceSymbol(
            named: "FileAttribute",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: fileAttributeSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = packageFQName + [interner.intern("FileAttribute"), typeParamName]
        let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(fileAttributeSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: fileAttributeSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: fileAttributeSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let fileAttributeType = types.make(.classType(ClassType(
            classSymbol: fileAttributeSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(fileAttributeType, for: fileAttributeSymbol)
        return fileAttributeSymbol
    }
}
