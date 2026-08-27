extension DataFlowSemaPhase {
    func registerSyntheticStringEncodingStubs(context: SyntheticStringStubContext) -> SymbolID {
        let (symbols, types, interner, kotlinTextPkg) = (context.symbols, context.types, context.interner, context.kotlinTextPkg); let (stringType, charSequenceSymbol, intType) = (context.stringType, context.charSequenceSymbol, context.intType)
        // --- STDLIB-145: String.toByteArray / encodeToByteArray ---
        let charsetSymbol = ensureClassSymbol(
            named: "Charset", in: kotlinTextPkg,
            symbols: symbols, interner: interner
        )
        let charsetType = types.make(.classType(ClassType(
            classSymbol: charsetSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(charsetType, for: charsetSymbol)
        let javaMathPkg = ensurePackage(
            path: ["java", "math"],
            symbols: symbols,
            interner: interner
        )
        let javaMathPkgSymbol = symbols.lookup(fqName: javaMathPkg)
        let bigDecimalSymbol = ensureClassSymbol(
            named: "BigDecimal",
            in: javaMathPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaMathPkgSymbol {
            symbols.setParentSymbol(javaMathPkgSymbol, for: bigDecimalSymbol)
        }
        let bigDecimalType = types.make(.classType(ClassType(
            classSymbol: bigDecimalSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(bigDecimalType, for: bigDecimalSymbol)

        // STDLIB-574: ByteArray / List<Int> internal representation
        let listIntType = makeListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: intType
        )
        let byteArrayType = makeNominalType(
            symbols: symbols,
            types: types,
            fqName: [interner.intern("kotlin"), interner.intern("ByteArray")]
        )

        // STDLIB-STR-125
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let stringClassSymbol = ensureClassSymbol(
            named: "String",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: stringClassSymbol)
        }
        types.stringClassSymbol = stringClassSymbol
        symbols.setDirectSupertypes([charSequenceSymbol], for: stringClassSymbol)
        types.setNominalDirectSupertypes([charSequenceSymbol], for: stringClassSymbol)
        for bytesType in [listIntType, byteArrayType] {
            registerStringConstructorFromBytes(
                ownerSymbol: stringClassSymbol,
                ownerType: stringType,
                parameters: [("bytes", bytesType), ("charset", charsetType)],
                externalLinkName: "__kk_bytearray_decodeToString_charset",
                symbols: symbols,
                interner: interner
            )
            // String(ByteArray) — default UTF-8 decoding
            registerStringConstructorFromBytes(
                ownerSymbol: stringClassSymbol,
                ownerType: stringType,
                parameters: [("bytes", bytesType)],
                externalLinkName: "__kk_bytearray_decodeToString",
                symbols: symbols,
                interner: interner
            )
        }

        return stringClassSymbol
    }
}
