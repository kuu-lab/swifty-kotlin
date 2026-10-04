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

    /// Classify a stdlib-typed symbol into its tracked collection kind using
    /// the once-per-pass `lookup.staticTypeClassification` tables — a single
    /// dictionary probe plus an element-wise package prefix check, instead of
    /// re-interning ~43 constant names per call.
    ///
    /// RF-LOWER-STATE-009: static type alone cannot tell a source Sequence
    /// object from a RuntimeSequenceBox (KSP-441〜447 moved the pipeline to
    /// Kotlin source, but some factories/bridges still hand back the runtime
    /// representation) — the `.sequence` result records only that the type is
    /// Sequence, via `Classification.sequenceType`. The confirmed-provenance
    /// facts (`Classification.sequence` / `.sequenceSourceObject`) are seeded
    /// in +PreScan.swift instead, from known factories/bridges/source
    /// declarations/copies.
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

    /// True when `symbol`'s declared receiver type is one of the bundled
    /// `asSequence()` overloads confirmed, by reading its body, to construct
    /// a fresh `object : Sequence<T>`: `Iterable`, `Iterator`, `CharSequence`,
    /// `Map` (Sequences.kt, StringCollectionConversions.kt, MapHOF.kt).
    ///
    /// Deliberately excludes two other source-backed overloads:
    ///  - `Array<T>.asSequence()` (ArrayHOF.kt) delegates to
    ///    `toList().asSequence()` in source too, but the array virtual-call
    ///    rewrite intercepts `asSequence()` ahead of source resolution for
    ///    any receiver tracked as an array and redirects it to
    ///    `kk_array_asSequence`, so this body never runs for such a receiver.
    ///  - `Sequence<T>.asSequence()` (identity, `= this`): the result's
    ///    provenance is the *receiver's* own, which a callee-only check like
    ///    this has no way to look up.
    /// Used only to confirm ``CollectionLiteralLoweringSupport/Classification/sequenceSourceObject``,
    /// never ``CollectionLiteralLoweringSupport/Classification/sequence`` — a
    /// name match here is evidence of a source object, not a runtime bridge.
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
