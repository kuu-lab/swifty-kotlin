enum NamedTypeArgumentSegments {
    static func validIndices(
        in namedType: NamedTypeRef,
        for target: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        imports: [ImportDecl],
        diagnostics: DiagnosticEngine?,
        range: SourceRange?
    ) -> Set<Int> {
        let segments = namedType.segments
        guard !segments.isEmpty else {
            return []
        }

        var validIndices = Set(segments.indices)
        let allowedEnclosingNames = enclosingClassifierFQNames(for: target, symbols: symbols)
        let targetFQName = symbols.symbol(target)?.fqName ?? []
        let segmentFQNames = resolvedSegmentFQNames(
            in: namedType,
            targetFQName: targetFQName,
            imports: imports
        )

        for index in segments.indices where !segments[index].args.isEmpty {
            if index < segments.count - 1 {
                guard let enclosingFQName = segmentFQNames[index],
                      allowedEnclosingNames.contains(enclosingFQName)
                else {
                    validIndices.remove(index)
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0496",
                        "Type arguments are not allowed for a non-inner nested class's qualifier.",
                        range: range
                    )
                    continue
                }
            }

            guard namedType.segments.count > 1,
                  let segmentFQName = segmentFQNames[index],
                  let segmentSymbol = symbols.lookupAll(fqName: segmentFQName)
                    .first(where: { isTypeSymbol($0, symbols: symbols) })
            else {
                continue
            }
            let expectedCount = typeParameterCount(for: segmentSymbol, symbols: symbols, types: types)
            guard segments[index].args.count > expectedCount else {
                continue
            }
            diagnostics?.error(
                "KSWIFTK-SEMA-0497",
                "Type argument count mismatch for qualified type segment: expected \(expectedCount) but got \(segments[index].args.count).",
                range: range
            )
        }
        return validIndices
    }

    private static func typeParameterCount(for symbolID: SymbolID, symbols: SymbolTable, types: TypeSystem) -> Int {
        guard let symbol = symbols.symbol(symbolID) else {
            return 0
        }
        if symbol.kind == .typeAlias {
            return symbols.typeAliasTypeParameters(for: symbolID).count
        }
        return max(
            types.nominalTypeParameterSymbols(for: symbolID).count,
            types.nominalTypeParameterVariances(for: symbolID).count
        )
    }

    private static func isTypeSymbol(_ symbolID: SymbolID, symbols: SymbolTable) -> Bool {
        guard let kind = symbols.symbol(symbolID)?.kind else {
            return false
        }
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            return true
        default:
            return false
        }
    }

    private static func resolvedSegmentFQNames(
        in namedType: NamedTypeRef,
        targetFQName: [InternedString],
        imports: [ImportDecl]
    ) -> [[InternedString]?] {
        let path = namedType.path
        guard let lastIndex = path.indices.last else {
            return []
        }

        if path.count <= targetFQName.count,
           Array(targetFQName.suffix(path.count)) == path
        {
            let offset = targetFQName.count - path.count
            return path.indices.map { index in
                Array(targetFQName.prefix(offset + index + 1))
            }
        }

        if let first = path.first,
           let alias = imports.first(where: { !$0.isWildcard && $0.alias == first })
        {
            let expandedPath = alias.path + Array(path.dropFirst())
            if expandedPath.count <= targetFQName.count,
               Array(targetFQName.suffix(expandedPath.count)) == expandedPath
            {
                let offset = targetFQName.count - expandedPath.count
                return path.indices.map { index in
                    let expandedIndex = alias.path.count - 1 + index
                    return Array(targetFQName.prefix(offset + expandedIndex + 1))
                }
            }
        }

        var result = Array(repeating: nil as [InternedString]?, count: path.count)
        result[lastIndex] = targetFQName
        return result
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
