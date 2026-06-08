
/// Synthetic stub for kotlin.io.OnErrorAction (STDLIB-IO-TYPE-007).
///
/// `OnErrorAction` is a Kotlin stdlib enum in the `kotlin.io` package with
/// two entries:
/// - `SKIP`      – skip the problematic file/directory and continue the walk
/// - `TERMINATE` – abort the walk immediately
///
/// This stub registers the enum class and its entries in the symbol table so
/// that name resolution and type checking succeed for code that references
/// `OnErrorAction.SKIP` / `OnErrorAction.TERMINATE` or declares a parameter
/// or return type of `OnErrorAction`.
///
/// Registration runs after `registerSyntheticFileIOStubs` (which ensures the
/// `kotlin.io` package symbol exists) so the parent link can always be
/// resolved.
///
/// At runtime, enum entries are materialized by `DataEnumSealedSynthesisPass`
/// as boxed ordinal ints via `kk_box_int(ordinal)` — no dedicated `@_cdecl`
/// functions are required for the singleton values themselves.
extension DataFlowSemaPhase {
    func registerSyntheticOnErrorActionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinIOPkg = ensurePackage(
            path: ["kotlin", "io"],
            symbols: symbols,
            interner: interner
        )

        let enumSymbol = ensureOnErrorActionEnumClass(
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(enumType, for: enumSymbol)

        setOnErrorActionEntryTypes(
            enumSymbol: enumSymbol,
            enumType: enumType,
            symbols: symbols
        )
    }

    // MARK: - Private helpers

    private func ensureOnErrorActionEnumClass(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("OnErrorAction")
        let fqName = pkg + [name]
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
        if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: enumSymbol)
        }

        // Register enum entries in declaration order: SKIP (ordinal 0), TERMINATE (ordinal 1).
        // Ordinals are computed by DataEnumSealedSynthesisPass from sibling field indices, so
        // declaration order MUST match the Kotlin stdlib definition.
        for entry in ["SKIP", "TERMINATE"] {
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

    /// Set propertyType on each enum entry so that resolveClassNameMemberValue
    /// (which checks `.field` + propertyType) can resolve
    /// `OnErrorAction.SKIP` / `OnErrorAction.TERMINATE`.
    private func setOnErrorActionEntryTypes(
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
}
