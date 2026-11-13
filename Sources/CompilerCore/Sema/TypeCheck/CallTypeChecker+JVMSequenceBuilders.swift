extension CallTypeChecker {
    /// Resolve the injected builder entry, including import aliases, before
    /// generic receiver-builder inference can consume its yield-only evidence.
    func jvmSequenceBuilderName(_ name: InternedString?, ctx: TypeInferenceContext, locals: LocalBindings) -> InternedString? {
        guard ctx.sema.requiresResolvedLibraryCalls, let name, locals[name] == nil else { return nil }
        var result: InternedString?
        for candidate in ctx.filterByVisibility(ctx.cachedScopeLookup(name)).visible {
            guard let symbol = ctx.cachedSymbol(candidate), symbol.kind == .function else { continue }
            let standard = symbol.declSite.map { driver.sourceManager?.origin(of: $0.start.file) == .residualStdlib } == true
            let knownNames = KnownCompilerNames(interner: ctx.interner)
            if standard, symbol.fqName.count == 3, symbol.fqName[0] == knownNames.kotlin, symbol.fqName[1] == knownNames.sequences, ["sequence", "iterator"].contains(ctx.interner.resolve(symbol.fqName[2])) {
                if let result, result != symbol.name { return nil }
                result = symbol.name
            } else if !standard, !symbol.flags.contains(.synthetic) { return nil }
        }
        return result
    }
}
