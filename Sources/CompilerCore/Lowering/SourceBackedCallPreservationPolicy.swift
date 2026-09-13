/// How a call site's callee resolved, as far as source-backed preservation is
/// concerned.
///
/// The lowering passes used to spell this out inline as a chain of
/// `guard let symbol, let sema = ctx.sema, sema.symbols.symbol(symbol) != nil`
/// followed by a separate `isSourceBackedSymbol` check, which left the
/// "no symbol at all" and "symbol id with no table entry" cases implicit.
/// Naming the four states makes them testable and gives RF-LOWER-CALL-008
/// onwards a vocabulary to narrow the preserved API sets against.
enum SourceBackedCalleeResolution: Equatable {
    /// The call carries no callee symbol — hand-built KIR, or a call the KIR
    /// builder emitted directly against a `kk_*` entry point — or Sema
    /// bindings are unavailable for this module.
    case unresolved
    /// A callee symbol id that is not present in the symbol table.
    case unknownSymbol
    /// Resolved to a declaration backed by source: a bundled Kotlin stdlib
    /// declaration, user code, or an imported library declaration.
    case sourceBacked
    /// Resolved to a declaration with no source body — a synthetic stub whose
    /// implementation is an external `kk_*` bridge. KSP-443 member aliases
    /// land here too: they are nil-site synthetic siblings of a source
    /// declaration, so `isSourceBackedSymbol` reports them as not source
    /// backed even though a source implementation of the same signature
    /// exists under the declaring package.
    case externalBridge
}

extension SourceBackedCalleeResolution {
    /// Classifies `symbol` without reinterpreting `isSourceBackedSymbol`:
    /// that predicate stays the single authority on what "source backed"
    /// means (RF-LOWER-CALL-007 must not change its meaning or the Sema
    /// flags behind it).
    init(symbol: SymbolID?, sema: SemaModule?) {
        guard let symbol, let sema else {
            self = .unresolved
            return
        }
        guard sema.symbols.symbol(symbol) != nil else {
            self = .unknownSymbol
            return
        }
        self = sema.symbols.isSourceBackedSymbol(symbol) ? .sourceBacked : .externalBridge
    }
}

/// The one place that decides whether a resolved collection-API call keeps the
/// Kotlin declaration overload resolution selected, instead of being rewritten
/// to a `kk_*` runtime entry point.
///
/// RF-LOWER-CALL-007: `CollectionLiteralConstructionLoweringPass` (direct
/// calls) and `CollectionVirtualCallRewriteLoweringPass` (virtual dispatch)
/// each carried their own copy of this decision as a `||` chain of interned
/// name comparisons. The copies agreed on 91 API names and diverged on twenty
/// more plus the shape of the array-conversion check, and nothing in either
/// file said so. Here the agreement is one set, each divergence is its own
/// named set, and the decision order of both original predicates is preserved
/// exactly — this task is an extraction, not a narrowing. RF-LOWER-CALL-008
/// onwards shrinks the sets one API family at a time.
///
/// The policy never reaches into `SemaModule` itself: callers hand it a
/// `SourceBackedCalleeResolution` and closures for the receiver facts, so the
/// original short-circuit order (cheap name test first, symbol-table and
/// arena lookups only on a name hit) survives the move.
struct SourceBackedCallPreservationPolicy {
    /// API names preserved by both the direct-call and the virtual-call entry
    /// point. Comments record the migration each group came from.
    let sharedAggregateNames: Set<InternedString>

    /// API names preserved only on virtual dispatch. Range/progression members
    /// reach lowering as virtual calls, so the direct-call predicate never
    /// listed them; `toList` is the one name that the direct path handles
    /// instead through `directArrayConversionNames`.
    let virtualOnlyAggregateNames: Set<InternedString>

    /// Array member names the direct-call path preserves when the first
    /// argument is an array expression tracked by the pre-scan.
    let directArrayConversionNames: Set<InternedString>

    /// Array conversion member names the virtual-call path preserves when the
    /// receiver's static type is one of `arrayReceiverTypeNames`. `size` is
    /// checked separately there, and unlike the direct path this set does not
    /// include `toList` — that name is in `virtualOnlyAggregateNames`.
    let virtualArrayConversionNames: Set<InternedString>

    /// Receiver class names the virtual-call array branches accept.
    let arrayReceiverTypeNames: Set<String>

    private let sizeName: InternedString
    private let mapName: InternedString
    private let filterName: InternedString

    init(lookup: CollectionLiteralLookupTables, interner: StringInterner) {
        sharedAggregateNames = [
            lookup.scanName,
            lookup.scanIndexedName,
            lookup.runningFoldName,
            lookup.runningFoldIndexedName,
            lookup.runningReduceName,
            lookup.runningReduceIndexedName,
            lookup.reduceIndexedName,
            lookup.reduceIndexedOrNullName,
            lookup.filterName,
            lookup.filterNotName,
            lookup.filterNotNullName,
            lookup.filterIndexedName,
            lookup.associateName,
            lookup.associateByName,
            lookup.associateWithName,
            lookup.associateToName,
            lookup.associateByToName,
            lookup.associateWithToName,
            lookup.groupByName,
            lookup.groupByToName,
            lookup.partitionName,
            lookup.unzipName,
            lookup.withIndexName,
            lookup.onEachName,
            lookup.onEachIndexedName,
            lookup.sumOfName,
            lookup.maxByOrNullName,
            lookup.minByOrNullName,
            // KSP-426: List sorting/extrema are bundled Kotlin source and must
            // not be redirected to the removed kk_list_* runtime exports.
            lookup.sortedName,
            lookup.sortedByName,
            lookup.sortedByDescendingName,
            lookup.sortedDescendingName,
            lookup.sortedWithName,
            lookup.maxName,
            lookup.maxByName,
            lookup.maxOfName,
            lookup.maxOfOrNullName,
            lookup.maxOfWithName,
            lookup.maxOfWithOrNullName,
            lookup.maxOrNullName,
            lookup.maxWithName,
            lookup.maxWithOrNullName,
            lookup.minName,
            lookup.minByName,
            lookup.minOfName,
            lookup.minOfOrNullName,
            lookup.minOfWithName,
            lookup.minOfWithOrNullName,
            lookup.minOrNullName,
            lookup.minWithName,
            lookup.minWithOrNullName,
            // KSP-421: List transform HOFs have Kotlin source implementations.
            lookup.mapName,
            lookup.mapIndexedName,
            lookup.mapNotNullName,
            lookup.mapIndexedNotNullName,
            lookup.mapToName,
            lookup.mapIndexedToName,
            lookup.mapNotNullToName,
            lookup.mapIndexedNotNullToName,
            lookup.flatMapName,
            lookup.flatMapIndexedName,
            lookup.flatMapToName,
            lookup.flatMapIndexedToName,
            lookup.flattenName,
            // KSP-430: Map higher-order functions have Kotlin source implementations.
            lookup.mapValuesName,
            lookup.mapValuesToName,
            lookup.mapKeysName,
            lookup.mapKeysToName,
            lookup.filterKeysName,
            lookup.filterValuesName,
            lookup.forEachName,
            // STDLIB-pipeline §5: take/drop have real require() validation in
            // SequenceWindowChunk.kt as of MIGRATION-SEQ-005. A resolved call
            // to that source declaration must not be short-circuited to a
            // runtime bridge.
            lookup.takeName,
            lookup.dropName,
            // KSP-423: List search and predicate HOFs have Kotlin source implementations.
            lookup.findName,
            lookup.findLastName,
            lookup.indexOfName,
            lookup.lastIndexOfName,
            lookup.indexOfFirstName,
            lookup.indexOfLastName,
            lookup.containsName,
            lookup.containsAllName,
            lookup.countName,
            lookup.anyName,
            lookup.allName,
            lookup.noneName,
            lookup.firstName,
            lookup.lastName,
            lookup.firstOrNullName,
            lookup.lastOrNullName,
            // KSP-658: generic Array<T>.copyOf / copyOfRange have Kotlin source implementations.
            lookup.copyOfName,
            lookup.copyOfRangeName,
        ]

        virtualOnlyAggregateNames = [
            // RF-LOWER-CALL-009 (#6762) removed these eleven from the direct
            // chain: nothing downstream of the direct path keys on them any
            // more, since the List-side legacy bridges are gone. The virtual
            // guard still lists them because the `sequenceExprIDs`-gated
            // branches in +CallRewriteHOFAccumulations.swift remain reachable
            // there, and whether those should fire for a source-backed
            // declaration whose receiver is a RuntimeSequenceBox is the
            // KSP-441 question RF-LOWER-CALL-014 owns. So they are virtual-only
            // rather than gone.
            lookup.foldName,
            lookup.foldIndexedName,
            lookup.foldRightName,
            lookup.foldRightIndexedName,
            lookup.reduceName,
            lookup.reduceOrNullName,
            lookup.reduceRightName,
            lookup.reduceRightOrNullName,
            lookup.reduceRightIndexedName,
            lookup.reduceRightIndexedOrNullName,
            lookup.scanReduceName,
            // KSP-312: Range/progression contains/isEmpty/iterator are now source-backed.
            lookup.isEmptyName,
            lookup.iteratorName,
            // KSP-453/454: Range/progression HOFs are now implemented in bundled Kotlin source.
            lookup.toListName,
            lookup.toIntArrayName,
            lookup.averageName,
            lookup.chunkedName,
            lookup.windowedName,
            interner.intern("random"),
            interner.intern("randomOrNull"),
        ]

        // KSP-1513/KSP-1516: source-backed Array<T>/primitive-array members on
        // literal arrays must keep their selected Kotlin declaration. The
        // source body may delegate to a typed private runtime bridge.
        directArrayConversionNames = [
            lookup.sizeName, lookup.toListName, lookup.sliceArrayName,
            lookup.reversedArrayName, lookup.asListName, lookup.toTypedArrayName,
        ]

        // KSP-1516: array conversion members are bundled Kotlin source. Keep
        // the selected declaration so its source body is emitted instead of
        // the removed synthetic runtime shortcuts.
        virtualArrayConversionNames = [
            lookup.sliceArrayName, lookup.reversedArrayName,
            lookup.asListName, lookup.toTypedArrayName,
        ]

        arrayReceiverTypeNames = [
            "IntArray", "LongArray", "ShortArray", "ByteArray",
            "CharArray", "BooleanArray", "DoubleArray", "FloatArray",
            "UByteArray", "UShortArray", "UIntArray", "ULongArray", "Array",
        ]

        sizeName = lookup.sizeName
        mapName = lookup.mapName
        filterName = lookup.filterName
    }

    /// Direct-call decision, in the order the inlined predicate used: array
    /// conversion on a tracked array literal first, then the shared API set,
    /// then the two Sequence runtime-representation exceptions.
    ///
    /// `receiverIsTrackedArrayLiteral` folds in the original
    /// `!arguments.isEmpty && state.arrayExprIDs.contains(arguments[0])`, and
    /// `receiverIsTrackedRuntimeSequence` the `sequenceExprIDs` /
    /// `arrayExprIDs` pair, so both stay behind the name test.
    func preservesDirectCall(
        callee: InternedString,
        resolution: @autoclosure () -> SourceBackedCalleeResolution,
        receiverIsTrackedArrayLiteral: @autoclosure () -> Bool,
        receiverIsTrackedRuntimeSequence: @autoclosure () -> Bool,
        calleeHasSequenceReceiverType: @autoclosure () -> Bool
    ) -> Bool {
        if directArrayConversionNames.contains(callee),
           receiverIsTrackedArrayLiteral(),
           resolution() == .sourceBacked
        {
            return true
        }

        guard sharedAggregateNames.contains(callee),
              resolution() == .sourceBacked
        else {
            return false
        }

        // STDLIB-pipeline §5 / KSP-441: source Sequence.map/filter walk a source
        // Sequence object via iterator(), but RuntimeSequenceBox (from
        // kk_array_asSequence / kk_list_asSequence) has no itable map entry and
        // must go through kk_sequence_map/filter.
        if receiverIsTrackedRuntimeSequence(),
           callee == mapName || callee == filterName
        {
            return false
        }

        // A Sequence-typed receiver may still be a RuntimeSequenceBox at run
        // time (e.g. a parameter fed by asSequence()), which the source
        // iterator cannot walk. flatMap/flatMapIndexed are excluded: their
        // bundled source implementations traverse the receiver through the
        // shared iterator bridge and are the KSP-441 source pipeline.
        if callee == mapName || callee == filterName,
           calleeHasSequenceReceiverType()
        {
            return false
        }
        return true
    }

    /// Virtual-dispatch decision, in the order the inlined predicate used:
    /// `size`, then the array conversion members, then the shared plus
    /// virtual-only API sets. Both array branches answer with set membership
    /// once the receiver class resolves, and fall through to the API sets when
    /// it does not — `receiverArrayClassName` returns nil for that case.
    ///
    /// Unlike `preservesDirectCall` there is no Sequence exception here;
    /// runtime-backed Sequence receivers are handled by
    /// `rewriteSequenceVirtualCall`, which RF-LOWER-CALL-014 revisits.
    func preservesVirtualCall(
        callee: InternedString,
        resolution: @autoclosure () -> SourceBackedCalleeResolution,
        receiverArrayClassName: () -> String?
    ) -> Bool {
        // KSP-1513: array `size` is a bundled Kotlin declaration, so do not
        // replace it with the generic runtime bridge when the receiver is an
        // Array<T> or primitive array.
        if callee == sizeName,
           resolution() == .sourceBacked,
           let className = receiverArrayClassName()
        {
            return arrayReceiverTypeNames.contains(className)
        }

        if virtualArrayConversionNames.contains(callee),
           resolution() == .sourceBacked,
           let className = receiverArrayClassName()
        {
            return arrayReceiverTypeNames.contains(className)
        }

        guard sharedAggregateNames.contains(callee)
            || virtualOnlyAggregateNames.contains(callee)
        else {
            return false
        }
        return resolution() == .sourceBacked
    }
}
