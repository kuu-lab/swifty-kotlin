
/// Synthetic anchors for MatchResult and Destructured.
///
/// KSP-486: the MatchResult / MatchGroup / MatchGroupCollection / Destructured
/// member layer is declared in Kotlin
/// (`Sources/CompilerCore/Stdlib/kotlin/text/MatchResult.kt`), so only the
/// opaque `MatchResult` / `MatchResult.Destructured` anchors are registered here.
///
/// KSP-487: Regex / RegexOption and their engine entry points are now declared
/// in bundled Kotlin source (`Sources/CompilerCore/Stdlib/kotlin/text/Regex.kt`).
extension DataFlowSemaPhase {
    func registerSyntheticRegexStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTextPkg = ensureKotlinTextPackage(symbols: symbols, interner: interner)

        // --- Class symbols ---
        let matchResultSymbol = ensureClassSymbol(named: "MatchResult", in: kotlinTextPkg, symbols: symbols, interner: interner)

        // --- STDLIB-TEXT-TYPE-010: MatchResult.Destructured nested class ---
        // Members live in Kotlin; only the type anchor is needed here so that the
        // bundled `kotlin.text.MatchResult.Destructured` extensions can resolve.
        let matchResultFQName = symbols.symbol(matchResultSymbol)?.fqName ?? kotlinTextPkg + [interner.intern("MatchResult")]
        _ = ensureNestedClassSymbol(
            named: "Destructured",
            inFQName: matchResultFQName,
            parentSymbol: matchResultSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    /// Defines a nested class symbol inside `parentFQName` if it doesn't already exist.
    private func ensureNestedClassSymbol(
        named name: String,
        inFQName parentFQName: [InternedString],
        parentSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = parentFQName + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        let nestedSymbol = symbols.define(
            kind: .class,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(parentSymbol, for: nestedSymbol)
        return nestedSymbol
    }

    private func ensureKotlinTextPackage(
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
}
