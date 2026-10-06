extension DataEnumSealedSynthesisPass {
    /// Annotation instances implement Any's methods without acquiring data-class APIs.
    func synthesizeAnnotationHelpers(
        nominalSymbol: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        ctx: KIRContext
    ) {
        func syntheticMember(_ name: String) -> SymbolID? {
            sema.symbols.lookupAll(fqName: nominalSymbol.fqName + [ctx.interner.intern(name)]).first {
                sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
            }
        }
        let properties = dataClassPropertySymbols(owner: nominalSymbol, symbols: sema.symbols)
        appendSyntheticDataClassEqualsIfNeeded(
            owner: nominalSymbol, properties: properties,
            existingSymbol: syntheticMember("equals"), module: module, sema: sema,
            existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
        )
        appendSyntheticDataClassHashCodeIfNeeded(
            owner: nominalSymbol, existingSymbol: syntheticMember("hashCode"),
            module: module, sema: sema,
            existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
        )
        appendSyntheticDataClassToStringIfNeeded(
            name: ctx.interner.intern("toString"), owner: nominalSymbol,
            properties: properties,
            existingSymbol: syntheticMember("toString"), module: module, sema: sema,
            existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
        )
    }

    /// Canonical NaN bits implement boxed Float/Double equality for annotation members.
    func annotationCanonicalMemberValue(
        _ value: KIRExprID, type: TypeID, module: KIRModule, sema: SemaModule,
        interner: StringInterner, body: inout [KIRInstruction]
    ) -> KIRExprID {
        let callee: String
        switch sema.types.kind(of: type) {
        case .primitive(.float, .nonNull): callee = "__kk_float_toBits"
        case .primitive(.double, .nonNull): callee = "__kk_double_toBits"
        default: return value
        }
        let bits = module.arena.appendTemporary(type: sema.types.longType)
        body.append(.call(
            symbol: nil, callee: interner.intern(callee), arguments: [value],
            result: bits, canThrow: false, thrownResult: nil
        ))
        return bits
    }

    func isAnnotationArrayType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(sema.types.makeNonNullable(type), sema: sema) else {
            return false
        }
        return symbol.fqName == [interner.intern("kotlin"), symbol.name]
            && KnownCompilerNames(interner: interner).isArrayLikeName(symbol.name)
    }
}
