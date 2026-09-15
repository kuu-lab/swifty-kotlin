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
        interner: StringInterner,
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
        guard let trackedKind = trackedStaticTypeKind(of: symbol, interner: interner) else {
            return
        }
        state.tag(expr, as: trackedKind)
    }

    func trackedStaticTypeKind(
        of symbol: SemanticSymbol,
        interner: StringInterner
    ) -> CollectionLiteralTrackedStaticTypeKind? {
        let kotlinPackage = [interner.intern("kotlin")]
        let collectionsPackage = kotlinPackage + [interner.intern("collections")]
        let sequencesPackage = kotlinPackage + [interner.intern("sequences")]

        let listNames = [
            interner.intern("List"),
            interner.intern("MutableList"),
            interner.intern("ArrayList"),
            interner.intern("AbstractList"),
            interner.intern("AbstractMutableList"),
        ]
        if matchesStdlibType(symbol, package: collectionsPackage, simpleNames: listNames) {
            return .list
        }

        let setNames = [
            interner.intern("Set"),
            interner.intern("MutableSet"),
            interner.intern("HashSet"),
            interner.intern("LinkedHashSet"),
            interner.intern("AbstractSet"),
            interner.intern("AbstractMutableSet"),
        ]
        if matchesStdlibType(symbol, package: collectionsPackage, simpleNames: setNames) {
            return .set
        }

        let mapNames = [
            interner.intern("Map"),
            interner.intern("MutableMap"),
            interner.intern("HashMap"),
            interner.intern("LinkedHashMap"),
            interner.intern("AbstractMap"),
            interner.intern("AbstractMutableMap"),
        ]
        if matchesStdlibType(symbol, package: collectionsPackage, simpleNames: mapNames) {
            return .map
        }

        let arrayNames = [
            interner.intern("Array"),
            interner.intern("IntArray"),
            interner.intern("LongArray"),
            interner.intern("DoubleArray"),
            interner.intern("FloatArray"),
            interner.intern("BooleanArray"),
            interner.intern("CharArray"),
            interner.intern("ByteArray"),
            interner.intern("ShortArray"),
            interner.intern("UByteArray"),
            interner.intern("UShortArray"),
            interner.intern("UIntArray"),
            interner.intern("ULongArray"),
        ]
        if matchesStdlibType(symbol, package: kotlinPackage, simpleNames: arrayNames) {
            return .array
        }

        // RF-LOWER-STATE-009: static type alone cannot tell a source Sequence
        // object from a RuntimeSequenceBox (KSP-441〜447 moved the pipeline to
        // Kotlin source, but some factories/bridges still hand back the
        // runtime representation) — this records only that the type is
        // Sequence, via `Classification.sequenceType`. The confirmed-
        // provenance facts (`Classification.sequence` /
        // `.sequenceSourceObject`) are seeded in +PreScan.swift instead, from
        // known factories/bridges/source declarations/copies.
        if matchesStdlibType(symbol, package: sequencesPackage, simpleNames: [interner.intern("Sequence")]) {
            return .sequence
        }

        if matchesStdlibType(symbol, package: kotlinPackage, simpleNames: [interner.intern("String")]) {
            return .string
        }

        return nil
    }

    private func matchesStdlibType(
        _ symbol: SemanticSymbol,
        package: [InternedString],
        simpleNames: [InternedString]
    ) -> Bool {
        if symbol.fqName.isEmpty {
            return symbol.flags.contains(.synthetic) && simpleNames.contains(symbol.name)
        }
        guard symbol.fqName.count == package.count + 1,
              let simpleName = symbol.fqName.last,
              simpleNames.contains(simpleName)
        else {
            return false
        }
        return Array(symbol.fqName.dropLast()) == package
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
        interner: StringInterner
    ) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: symbol),
              let receiverType = signature.receiverType,
              let (_, classSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
        else {
            return false
        }
        let kotlinPackage = [interner.intern("kotlin")]
        let collectionsPackage = kotlinPackage + [interner.intern("collections")]
        let confirmedOwners: [[InternedString]] = [
            collectionsPackage + [interner.intern("Iterable")],
            collectionsPackage + [interner.intern("Iterator")],
            collectionsPackage + [interner.intern("Map")],
            kotlinPackage + [interner.intern("CharSequence")],
        ]
        return confirmedOwners.contains(classSymbol.fqName)
    }
}
