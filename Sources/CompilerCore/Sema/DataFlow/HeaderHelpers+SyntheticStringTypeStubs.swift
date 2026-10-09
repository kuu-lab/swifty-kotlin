extension DataFlowSemaPhase {
    /// Build a type from an already-registered stdlib type shell.
    ///
    /// The collection/sequence interfaces and the primitive array classes are
    /// registered by `registerSyntheticCollectionStubs` or by bundled Kotlin
    /// source before the String stubs run, so a lookup is sufficient here.
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




}
