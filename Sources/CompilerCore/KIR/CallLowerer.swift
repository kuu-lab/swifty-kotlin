import RuntimeABI

final class CallLowerer {
    /// Bitmask of object slot indices holding a data class's primary-constructor properties.
    /// Returns nil when the layout is unknown or a slot does not fit in the mask, in which case
    /// the runtime keeps comparing every stored slot.
    func dataClassFieldSlotMask(owner ownerSymbol: SymbolID, sema: SemaModule) -> Int64? {
        guard let owner = sema.symbols.symbol(ownerSymbol),
              let fieldOffsets = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets
        else {
            return nil
        }
        let children = sema.symbols.children(ofFQName: owner.fqName).compactMap { sema.symbols.symbol($0) }
        guard let primaryConstructor = children.filter({ $0.kind == .constructor }).min(by: { lhs, rhs in
            let lhsOffset = lhs.declSite?.start.offset ?? Int.max
            let rhsOffset = rhs.declSite?.start.offset ?? Int.max
            return lhsOffset != rhsOffset ? lhsOffset < rhsOffset : lhs.id.rawValue < rhs.id.rawValue
        }) else {
            return nil
        }
        let parameterNames = sema.symbols.functionSignature(for: primaryConstructor.id)?
            .valueParameterSymbols.compactMap { sema.symbols.symbol($0)?.name } ?? []
        let properties = Dictionary(
            children.filter { $0.kind == .property && !$0.flags.contains(.synthetic) }.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var mask: Int64 = 0
        for name in parameterNames {
            guard let property = properties[name],
                  let offset = fieldOffsets[property.id],
                  offset >= 0, offset < 62
            else {
                return nil
            }
            mask |= Int64(1) << Int64(offset)
        }
        return mask
    }

    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    /// Returns whether a direct lambda argument may use a label-free return to
    /// leave the caller. Kotlin permits this only for function-type parameters
    /// of inline functions that are neither `crossinline` nor `noinline`.
    func allowsNonLocalReturn(
        argumentExpr: ExprID,
        argumentIndex: Int,
        ast: ASTModule,
        sema: SemaModule,
        callBinding: CallBinding?,
        chosen: SymbolID?
    ) -> Bool {
        guard case .lambdaLiteral = ast.arena.expr(argumentExpr),
              let chosen,
              sema.symbols.symbol(chosen)?.flags.contains(.inlineFunction) == true,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return false
        }
        let parameterIndex = callBinding?.parameterMapping[argumentIndex] ?? argumentIndex
        guard signature.parameterTypes.indices.contains(parameterIndex) else {
            return false
        }
        let parameterType = signature.parameterTypes[parameterIndex]
        guard case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) else {
            return false
        }
        // Older synthetic/imported signatures may not carry the parallel flag
        // array. Preserve their historical behavior conservatively.
        guard signature.valueParameterAllowsNonLocalReturn.indices.contains(parameterIndex) else {
            return true
        }
        return signature.valueParameterAllowsNonLocalReturn[parameterIndex]
    }

    // MARK: - REFL-005: typeOf<T>() Lowering

}
