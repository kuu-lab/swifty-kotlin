extension CallTypeChecker {
    /// Resolve the injected builder entry, including import aliases, before
    /// generic receiver-builder inference can consume its yield-only evidence.
    func jvmSequenceBuilderName(_ name: InternedString?, ctx: TypeInferenceContext, locals: LocalBindings) -> InternedString? {
        guard ctx.sema.requiresResolvedLibraryCalls, let name, locals[name] == nil else { return nil }
        var result: InternedString?
        for candidate in ctx.filterByVisibility(ctx.cachedScopeLookup(name)).visible {
            guard let symbol = ctx.cachedSymbol(candidate), symbol.kind == .function else { continue }
            let standard = symbol.declSite.map { driver.sourceManager?.origin(of: $0.start.file) == .residualStdlib } == true
            let path = symbol.fqName.map(ctx.interner.resolve)
            if standard, path.count == 3, path[0] == "kotlin", path[1] == "sequences", ["sequence", "iterator"].contains(path[2]) {
                if let result, result != symbol.name { return nil }
                result = symbol.name
            } else if !standard, !symbol.flags.contains(.synthetic) { return nil }
        }
        return result
    }
}
