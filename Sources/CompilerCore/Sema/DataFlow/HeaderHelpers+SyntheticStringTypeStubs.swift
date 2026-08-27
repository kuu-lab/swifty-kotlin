extension DataFlowSemaPhase {
    func registerSyntheticStringTypeStubs(context: SyntheticStringStubContext) {
        let (symbols, types, interner, kotlinTextPkg) = (context.symbols, context.types, context.interner, context.kotlinTextPkg); let (appendableSymbol, appendableType, intType, charType) = (context.appendableSymbol, context.appendableType, context.intType, context.charType)
        let nullableCharSequenceType = context.nullableCharSequenceType
        /// Build a type from an already-registered stdlib type shell.
        ///
        /// The collection/sequence interfaces and the primitive array classes are
        /// registered by `registerSyntheticCollectionStubs` or by bundled Kotlin
        /// source before the String stubs run, so a lookup is sufficient here.
        // --- STDLIB-TEXT-TYPE-001: kotlin.text.Appendable interface surface ---
        // BUG-172: all three overloads need an externalLinkName. StringBuilder is
        // the sole implementer and bypasses kk_object_new construction (see the
        // BUG-044 note in RuntimeStringBuilder.swift), so it never registers itable
        // entries — a call through the bare `Appendable` interface type for an
        // overload with no externalLinkName falls through to itable dispatch and
        // panics with "method not found in vtable/itable".
        registerAppendableMemberFunction(
            named: "append",
            externalLinkName: "__kk_string_builder_append_char",
            ownerSymbol: appendableSymbol,
            ownerType: appendableType,
            parameters: [("value", charType, false, false)],
            returnType: appendableType,
            symbols: symbols,
            interner: interner
        )
        registerAppendableMemberFunction(
            named: "append",
            externalLinkName: "__kk_string_builder_append_obj",
            ownerSymbol: appendableSymbol,
            ownerType: appendableType,
            parameters: [("value", nullableCharSequenceType, false, false)],
            returnType: appendableType,
            symbols: symbols,
            interner: interner
        )
        registerAppendableMemberFunction(
            named: "append",
            externalLinkName: "__kk_string_builder_append_range",
            ownerSymbol: appendableSymbol,
            ownerType: appendableType,
            parameters: [
                ("value", nullableCharSequenceType, false, false),
                ("startIndex", intType, false, false),
                ("endIndex", intType, false, false),
            ],
            returnType: appendableType,
            symbols: symbols,
            interner: interner,
            canThrow: true
        )
        // --- STDLIB-TEXT-TYPE-003: kotlin.text.Typography object surface ---
        let typographySymbol = ensureSyntheticObjectSymbol(
            named: "Typography",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        let typographyType = types.make(.classType(ClassType(
            classSymbol: typographySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(typographyType, for: typographySymbol)
        if let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg) {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: typographySymbol)
        }
        for (name, scalar) in typographyCharConstants {
            registerTypographyCharConstant(
                ownerSymbol: typographySymbol,
                name: name,
                scalar: scalar,
                charType: charType,
                symbols: symbols,
                interner: interner
            )
        }
    }
    func makeStdlibShellType(
        symbols: SymbolTable,
        types: TypeSystem,
        fqName: [InternedString],
        args: [TypeArg]
    ) -> TypeID {
        guard let symbol = symbols.lookup(fqName: fqName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: args,
            nullability: .nonNull
        )))
    }
    func makeListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        makeStdlibShellType(
            symbols: symbols,
            types: types,
            fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ],
            args: [.out(elementType)]
        )
    }

    func makeCollectionType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        makeStdlibShellType(
            symbols: symbols,
            types: types,
            fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Collection"),
            ],
            args: [.out(elementType)]
        )
    }

    func makeSequenceType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        makeStdlibShellType(
            symbols: symbols,
            types: types,
            fqName: [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                interner.intern("Sequence"),
            ],
            args: [.out(elementType)]
        )
    }

    func makeNominalType(
        symbols: SymbolTable,
        types: TypeSystem,
        fqName: [InternedString]
    ) -> TypeID {
        makeStdlibShellType(symbols: symbols, types: types, fqName: fqName, args: [])
    }

    func makeListOfStringType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        makeListType(symbols: symbols, types: types, interner: interner, elementType: types.stringType)
    }
}
