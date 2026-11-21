enum CollectionLiteralTrackedStaticTypeKind {
    case list
    case set
    case map
    case array
    case sequence
    case string
}

extension CollectionLiteralLoweringSupport {
    func classifyTrackedExprByStaticType(
        _ expr: KIRExprID,
        module: KIRModule,
        sema: SemaModule?,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState
    ) {
        let raw = expr.rawValue
        if state.listExprIDs.contains(raw) || state.setExprIDs.contains(raw)
            || state.mapExprIDs.contains(raw) || state.arrayExprIDs.contains(raw)
            || state.sequenceExprIDs.contains(raw) || state.stringExprIDs.contains(raw)
            || state.sequenceTypeExprIDs.contains(raw)
        {
            return
        }
        guard let sema,
              let typeID = module.arena.exprType(expr)
        else {
            return
        }
        let nonNullType = sema.types.makeNonNullable(typeID)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return
        }
        // Route every tracked kind through `Classification.init(_:)` (via
        // `state.tag`) instead of a hand-written switch that inserts into a
        // raw set here: a second, independent mapping is how `.sequence`'s
        // case could silently insert into `sequenceExprIDs` (the confirmed-
        // `RuntimeSequenceBox` set) instead of `sequenceTypeExprIDs` once the
        // Sequence case below started returning non-nil again
        // (RF-LOWER-STATE-009). `seedCollectionExprIDsFromStaticTypes` in
        // +PreScan.swift already goes through `state.tag` for this reason.
        guard let trackedKind = trackedStaticTypeKind(of: symbol, lookup: lookup) else {
            return
        }
        state.tag(expr, as: trackedKind)
    }

    func trackedStaticTypeKind(
        of symbol: SemanticSymbol,
        lookup: CollectionLiteralLookupTables
    ) -> CollectionLiteralTrackedStaticTypeKind? {
        let names = lookup.staticTypeClassification
        if symbol.fqName.isEmpty {
            guard symbol.flags.contains(.synthetic),
                  let entry = names.trackedKindBySimpleName[symbol.name]
            else {
                return nil
            }
            return entry.kind
        }
        guard let simpleName = symbol.fqName.last,
              let entry = names.trackedKindBySimpleName[simpleName],
              symbol.fqName.count == entry.package.count + 1,
              symbol.fqName.dropLast().elementsEqual(entry.package)
        else {
            return nil
        }
        return entry.kind
    }

    func isKnownSourceObjectConstructingAsSequenceReceiver(
        symbol: SymbolID,
        sema: SemaModule,
        lookup: CollectionLiteralLookupTables
    ) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: symbol),
              let receiverType = signature.receiverType,
              let (_, classSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
        else {
            return false
        }
        return lookup.staticTypeClassification.sourceObjectConstructingAsSequenceReceivers
            .contains(classSymbol.fqName)
    }
}
