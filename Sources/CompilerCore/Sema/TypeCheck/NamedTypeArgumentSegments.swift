enum NamedTypeArgumentSegments {
    static func validIndices(
        in namedType: NamedTypeRef,
        for target: SymbolID,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine?,
        range: SourceRange?
    ) -> Set<Int> {
        let segments = namedType.segments
        guard !segments.isEmpty else {
            return []
        }

        var validIndices = Set(segments.indices)
        let outerArgumentIndices = segments.indices.dropLast().filter { !segments[$0].args.isEmpty }
        guard !outerArgumentIndices.isEmpty else {
            return validIndices
        }

        let allowedEnclosingNames = enclosingClassifierFQNames(for: target, symbols: symbols)
        let targetFQName = symbols.symbol(target)?.fqName ?? []
        let path = namedType.path
        let hasMatchingPathSuffix = path.count <= targetFQName.count
            && Array(targetFQName.suffix(path.count)) == path
        let pathOffset = hasMatchingPathSuffix ? targetFQName.count - path.count : 0

        for index in outerArgumentIndices {
            let enclosingFQName = hasMatchingPathSuffix
                ? Array(targetFQName.prefix(pathOffset + index + 1))
                : []
            guard !enclosingFQName.isEmpty, allowedEnclosingNames.contains(enclosingFQName) else {
                validIndices.remove(index)
                diagnostics?.error(
                    "KSWIFTK-SEMA-0496",
                    "Type arguments are not allowed for a non-inner nested class's qualifier.",
                    range: range
                )
                continue
            }
        }
        return validIndices
    }

    private static func enclosingClassifierFQNames(
        for target: SymbolID,
        symbols: SymbolTable
    ) -> Set<[InternedString]> {
        guard symbols.symbol(target)?.flags.contains(.innerClass) == true else {
            return []
        }

        var result: Set<[InternedString]> = []
        var ownerID = symbols.parentSymbol(for: target)
        while let currentID = ownerID, let owner = symbols.symbol(currentID) {
            switch owner.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                result.insert(owner.fqName)
            default:
                break
            }
            guard owner.flags.contains(.innerClass) else {
                break
            }
            ownerID = symbols.parentSymbol(for: currentID)
        }
        return result
    }
}
