
extension CallTypeChecker {
    func comparisonSpecialCallKind(
        for calleeName: InternedString,
        argCount: Int,
        resolvedParamType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> StdlibSpecialCallKind? {
        if locals[calleeName] != nil {
            return nil
        }
        let visibleCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        guard !visibleCandidates.isEmpty else {
            return nil
        }
        let expectedPrefix = [ctx.interner.intern("kotlin"), ctx.interner.intern("comparisons")]
        // Only consider top-level (non-extension, non-member) functions; extension
        // functions such as Sequence.maxOf share the same short name but are not
        // callable without a receiver and should not block the primitive fast path.
        let topLevelCandidates = visibleCandidates.filter { symbolID in
            guard let signature = ctx.sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == nil
        }
        let comparisonCandidates = topLevelCandidates.filter { symbolID in
            guard let symbol = ctx.sema.symbols.symbol(symbolID) else { return false }
            return symbol.fqName.count >= expectedPrefix.count
                && Array(symbol.fqName.prefix(expectedPrefix.count)) == expectedPrefix
        }
        guard !comparisonCandidates.isEmpty, topLevelCandidates.count == comparisonCandidates.count else {
            return nil
        }
        let resolvedName = ctx.interner.resolve(calleeName)
        let types = ctx.sema.types
        let supportedNumericTypes = [types.intType, types.longType, types.doubleType, types.floatType]
        let numericParamType = resolvedParamType.flatMap { paramType in
            supportedNumericTypes.first(where: { $0 == paramType })
        }
        guard let numericParamType else {
            return nil
        }

        if argCount == 3 {
            switch resolvedName {
            case "maxOf":
                if numericParamType == types.longType { return .maxOfLong3 }
                if numericParamType == types.doubleType { return .maxOfDouble3 }
                if numericParamType == types.floatType { return .maxOfFloat3 }
                return .maxOfInt3
            case "minOf":
                if numericParamType == types.longType { return .minOfLong3 }
                if numericParamType == types.doubleType { return .minOfDouble3 }
                if numericParamType == types.floatType { return .minOfFloat3 }
                return .minOfInt3
            default:
                return nil
            }
        }

        // 2-arg overloads
        switch resolvedName {
        case "maxOf":
            if numericParamType == types.longType { return .maxOfLong }
            if numericParamType == types.doubleType { return .maxOfDouble }
            if numericParamType == types.floatType { return .maxOfFloat }
            return .maxOfInt
        case "minOf":
            if numericParamType == types.longType { return .minOfLong }
            if numericParamType == types.doubleType { return .minOfDouble }
            if numericParamType == types.floatType { return .minOfFloat }
            return .minOfInt
        default:
            return nil
        }
    }
}
