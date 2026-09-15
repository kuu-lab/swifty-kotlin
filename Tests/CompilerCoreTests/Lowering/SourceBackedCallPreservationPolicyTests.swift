#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

/// RF-LOWER-CALL-007: pin the boundary that RF-LOWER-CALL-008〜015 narrow.
///
/// Before this task the "keep the selected Kotlin declaration" decision lived
/// twice — once in `CollectionLiteralLoweringPass+CallRewrite.swift` for direct
/// calls and once in `CollectionLiteralLoweringPass+VirtualCallRewrite.swift`
/// for virtual dispatch — as two `||` chains of interned name comparisons. The
/// chains agreed on 102 API names at extraction time and diverged on nine more
/// plus the shape of the array-conversion check, and nothing in either file
/// recorded which divergences were deliberate. RF-LOWER-CALL-008/009/010/011/012/013
/// have since narrowed the agreement to 51 names and grown the divergence to
/// 12. These tests fix both halves: the four callee
/// resolution states the decision rests on, and the exact direct/virtual
/// difference.
@Suite
struct SourceBackedCallPreservationPolicyTests {
    private static func makePolicy() -> (
        policy: SourceBackedCallPreservationPolicy,
        lookup: CollectionLiteralLookupTables,
        interner: StringInterner
    ) {
        let interner = StringInterner()
        let lookup = CollectionLiteralLookupTables(interner: interner)
        return (
            SourceBackedCallPreservationPolicy(lookup: lookup, interner: interner),
            lookup,
            interner
        )
    }

    // MARK: - callee resolution

    /// A call with no callee symbol — hand-built KIR, or a call the KIR builder
    /// emitted straight at a `kk_*` entry point — is `.unresolved`, never
    /// something the policy may preserve. The `symbol: nil` KIR shape that
    /// `CollectionLiteralLoweringTests` builds by hand depends on this.
    @Test
    func nilSymbolIsUnresolved() {
        let (sema, _, _, _) = makeSemaModule()
        #expect(SourceBackedCalleeResolution(symbol: nil, sema: sema) == .unresolved)
    }

    /// A pass may run without Sema bindings (`KIRContext.sema == nil`). The old
    /// predicates expressed this as a `guard let sema` that fell out to
    /// `return false`; naming it keeps that from being mistaken for
    /// `.externalBridge`.
    @Test
    func missingSemaIsUnresolved() {
        let (_, symbols, _, interner) = makeSemaModule()
        let symbol = symbols.define(
            kind: .function,
            name: interner.intern("map"),
            fqName: [interner.intern("map")],
            declSite: nil,
            visibility: .public
        )
        #expect(SourceBackedCalleeResolution(symbol: symbol, sema: nil) == .unresolved)
    }

    /// A symbol id with no table entry is distinct from having no symbol at
    /// all. Both decline preservation today; the old code could not tell them
    /// apart at all.
    @Test
    func symbolIDWithoutTableEntryIsUnknownSymbol() {
        let (sema, _, _, _) = makeSemaModule()
        let bogus = SymbolID(rawValue: 999_999)
        #expect(sema.symbols.symbol(bogus) == nil, "precondition: id must be absent")
        #expect(SourceBackedCalleeResolution(symbol: bogus, sema: sema) == .unknownSymbol)
    }

    /// A declaration with a source site is `.sourceBacked`. This is the state
    /// every user function and every migrated bundled stdlib declaration is in,
    /// and the only state that preserves a call.
    @Test
    func declarationWithSourceSiteIsSourceBacked() {
        let (sema, symbols, _, interner) = makeSemaModule()
        let sourceManager = SourceManager()
        let file = sourceManager.addFile(
            path: "fixture/Main.kt",
            contents: Data("fun map(x: Int) = x\n".utf8),
            origin: .user
        )
        let symbol = symbols.define(
            kind: .function,
            name: interner.intern("map"),
            fqName: [interner.intern("map")],
            declSite: SourceRange(
                start: SourceLocation(file: file, offset: 4),
                end: SourceLocation(file: file, offset: 7)
            ),
            visibility: .public
        )
        #expect(SourceBackedCalleeResolution(symbol: symbol, sema: sema) == .sourceBacked)
    }

    /// A synthetic stub with no source site is `.externalBridge`: its body is a
    /// `kk_*` entry point, so lowering is free to rewrite the call.
    @Test
    func syntheticStubWithoutSourceSiteIsExternalBridge() {
        let (sema, symbols, _, interner) = makeSemaModule()
        let symbol = symbols.define(
            kind: .function,
            name: interner.intern("map"),
            fqName: [interner.intern("map")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        #expect(SourceBackedCalleeResolution(symbol: symbol, sema: sema) == .externalBridge)
    }

    /// `.importedLibrary` is `.sourceBacked` even with no decl site — that is
    /// what `isSourceBackedSymbol` means, and RF-LOWER-CALL-007 must not
    /// redefine it. This is the `.kklib` artifact path: the same call that is
    /// preserved via a bundled source site under source injection is preserved
    /// via this flag when the stdlib arrives as an artifact.
    @Test
    func importedLibraryDeclarationIsSourceBacked() {
        let (sema, symbols, _, interner) = makeSemaModule()
        let symbol = symbols.define(
            kind: .function,
            name: interner.intern("map"),
            fqName: [interner.intern("lib"), interner.intern("map")],
            declSite: nil,
            visibility: .public,
            flags: [.importedLibrary]
        )
        #expect(SourceBackedCalleeResolution(symbol: symbol, sema: sema) == .sourceBacked)
    }

    /// A KSP-443 member alias is `.externalBridge`, not `.sourceBacked`:
    /// `HeaderCollection` registers it with `declSite: nil` and `.synthetic`
    /// beside a source-backed sibling so owner-based lookup resolves, and
    /// `isSourceBackedSymbol` reports the alias itself as not source backed.
    /// The alias shape is built here exactly as `HeaderCollection` builds it —
    /// source declaration under the declaring package, alias under the
    /// receiver class FQ reusing the signature and `externalLinkName`.
    @Test
    func memberAliasOfSourceDeclarationIsExternalBridge() {
        let (sema, symbols, types, interner) = makeSemaModule()
        let sourceManager = SourceManager()
        let bundledFile = sourceManager.addFile(
            path: "bundled/Sequences.kt",
            contents: Data("package kotlin.sequences\n".utf8),
            origin: .bundledStdlib
        )
        let pkg = [interner.intern("kotlin"), interner.intern("sequences")]
        let receiverClass = symbols.define(
            kind: .interface,
            name: interner.intern("Sequence"),
            fqName: pkg + [interner.intern("Sequence")],
            declSite: nil,
            visibility: .public
        )
        let memberName = interner.intern("toHashSet")
        let signature = FunctionSignature(
            receiverType: nil,
            parameterTypes: [],
            returnType: types.anyType
        )

        let source = symbols.define(
            kind: .function,
            name: memberName,
            fqName: pkg + [memberName],
            declSite: SourceRange(
                start: SourceLocation(file: bundledFile, offset: 24),
                end: SourceLocation(file: bundledFile, offset: 30)
            ),
            visibility: .public
        )
        symbols.setParentSymbol(receiverClass, for: source)
        symbols.setFunctionSignature(signature, for: source)
        symbols.setExternalLinkName("kk_sequence_toHashSet", for: source)

        let alias = symbols.define(
            kind: .function,
            name: memberName,
            fqName: symbols.symbol(receiverClass)!.fqName + [memberName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(receiverClass, for: alias)
        symbols.setFunctionSignature(signature, for: alias)
        symbols.setExternalLinkName("kk_sequence_toHashSet", for: alias)

        #expect(SourceBackedCalleeResolution(symbol: source, sema: sema) == .sourceBacked)
        #expect(
            SourceBackedCalleeResolution(symbol: alias, sema: sema) == .externalBridge,
            "the alias has no source site of its own, so it stays rewritable"
        )
    }

    // MARK: - direct / virtual divergence

    /// The whole point of the extraction: what the two predicates agreed on is
    /// one set, and every divergence is named. `virtualOnlyAggregateNames` is
    /// the complete list of names only virtual dispatch preserves.
    @Test
    func virtualOnlyNamesAreExactlyTheLiveRangeSequenceAndRandomMembers() {
        let (policy, _, interner) = Self.makePolicy()
        let resolved = Set(policy.virtualOnlyAggregateNames.map { interner.resolve($0) })
        #expect(
            resolved == [
                // RF-LOWER-CALL-009 leaves only the three accumulation names
                // with a live Range/progression consumer on the virtual path.
                "fold", "foldIndexed", "reduce",
                "isEmpty", "iterator",
                // RF-LOWER-CALL-011 (#6763) left `sorted` here alone out of the
                // List sort/extrema family, for the Range/progression consumer.
                // `toIntArray` dropped out when its lookup field was removed
                // by the Range toXxxArray cleanup (#6791).
                "toList", "average", "sorted", "chunked", "windowed",
                "random", "randomOrNull",
            ],
            "got: \(resolved.sorted())"
        )
        #expect(
            policy.virtualOnlyAggregateNames.isDisjoint(with: policy.sharedAggregateNames),
            "a name must be in exactly one of the two sets"
        )
    }

    /// The shared set is the direct-call predicate's list verbatim. A change in
    /// this count means an API family moved in or out of the policy, which
    /// RF-LOWER-CALL-008 onwards must do deliberately. RF-LOWER-CALL-010
    /// dropped the five search names (`indexOf`, `lastIndexOf`, `indexOfFirst`,
    /// `indexOfLast`, `containsAll`) that had no downstream rewrite,
    /// RF-LOWER-CALL-011 the 23 `sorted*` / `min*` / `max*` names,
    /// RF-LOWER-CALL-012 `maxByOrNull` / `minByOrNull` (their only rewrite, the
    /// Map branch in `+CallRewriteHOFCore.swift`, was deleted with them),
    /// RF-LOWER-CALL-008 the eight List transform/filter names in
    /// `listTransformDestinationAndOrphanNamesAreGone` below, and
    /// RF-LOWER-CALL-013 `copyOf` / `copyOfRange` (no Lowering rewrite has
    /// checked either name since KSP-1516; confirmed via a full-tree grep, not
    /// just the deleted array-conversion rewrite files).
    @Test
    func sharedAggregateNameCountMatchesTheExtractedPredicate() {
        let (policy, _, _) = Self.makePolicy()
        #expect(policy.sharedAggregateNames.count == 51, "got \(policy.sharedAggregateNames.count)")
    }

    /// The eight List accumulation names with no virtual consumer are no
    /// longer protected by policy. The remaining three names stay virtual-only
    /// because Range/progression lowering still keys on them; the eight
    /// Sequence-gated names stay in the shared set for RF-LOWER-CALL-014.
    @Test
    func deadVirtualAccumulationNamesAreGoneButLiveConsumersRemainProtected() {
        let (policy, lookup, interner) = Self.makePolicy()
        let removedNames = [
            "foldRight", "foldRightIndexed", "reduceOrNull", "reduceRight",
            "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull",
            "scanReduce",
        ]
        for name in removedNames {
            let interned = interner.intern(name)
            #expect(!policy.sharedAggregateNames.contains(interned), "\(name) remains shared")
            #expect(!policy.virtualOnlyAggregateNames.contains(interned), "\(name) remains virtual-only")
        }
        for name in [lookup.foldName, lookup.foldIndexedName, lookup.reduceName] {
            #expect(!policy.sharedAggregateNames.contains(name))
            #expect(policy.virtualOnlyAggregateNames.contains(name))
        }
        for name in [
            lookup.scanName, lookup.scanIndexedName, lookup.runningFoldName,
            lookup.runningFoldIndexedName, lookup.runningReduceName,
            lookup.runningReduceIndexedName, lookup.reduceIndexedName,
            lookup.reduceIndexedOrNullName,
        ] {
            #expect(policy.sharedAggregateNames.contains(name))
            #expect(!policy.virtualOnlyAggregateNames.contains(name))
        }
    }

    /// RF-LOWER-CALL-008 dropped the eight names whose only role in either
    /// predicate was shadowing a `.list`-owner rewrite that
    /// `StdlibSurfaceSpec.listHOFMembers` (KSP-421) had already emptied out:
    /// the six destination (`*To`) variants, plus `mapIndexedNotNull` and
    /// `filterNotNull`, which have no rewrite on any receiver kind at all. A
    /// merge that resurrected one of these would not change lowered KIR for a
    /// List receiver — nothing claims the name any more — so nothing but this
    /// assertion would catch the regression.
    ///
    /// The other nine List transform/filter names stay, because the same
    /// interned name still selects a live rewrite for a different receiver:
    /// `map` / `mapIndexed` / `mapNotNull` / `filterIndexed` / `filterNot` for
    /// Range/progression (`+VirtualCallRewrite+Range.swift` — `map` used to
    /// also share a Map receiver rewrite, but RF-LOWER-CALL-012 deleted that
    /// one as equally unreachable), and `flatMap` / `flatMapIndexed` /
    /// `flatten` for the Sequence pipeline/terminal rewrites. Dropping any of
    /// those would hand that receiver's source-backed declaration to the
    /// rewrite it currently shadows.
    @Test
    func listTransformDestinationAndOrphanNamesAreGone() {
        let (policy, lookup, _) = Self.makePolicy()
        for name in [
            lookup.mapToName, lookup.mapIndexedToName, lookup.mapNotNullToName,
            lookup.mapIndexedNotNullToName, lookup.flatMapToName, lookup.flatMapIndexedToName,
            lookup.mapIndexedNotNullName, lookup.filterNotNullName,
        ] {
            #expect(!policy.sharedAggregateNames.contains(name))
            #expect(!policy.virtualOnlyAggregateNames.contains(name))
        }
        for name in [
            lookup.mapName, lookup.filterName, lookup.flatMapName,
            lookup.mapIndexedName, lookup.mapNotNullName,
            lookup.filterIndexedName, lookup.filterNotName,
            lookup.flatMapIndexedName, lookup.flattenName,
        ] {
            #expect(policy.sharedAggregateNames.contains(name))
        }
    }

    /// RF-LOWER-CALL-011 removed the List sort/extrema family from the direct
    /// chain but left `sorted` in the virtual one for its Range consumer. The
    /// sets are what carry that asymmetry now, and a merge that restored the
    /// deleted names would not change lowered KIR — these names guard nothing —
    /// so nothing but this assertion would catch the regression.
    ///
    /// Only the four names whose `CollectionLiteralLookupTables` properties
    /// outlived RF-LOWER-CALL-011 can regress silently; it deleted the other
    /// nineteen properties outright, so naming those would not compile.
    /// `max` / `maxOrNull` / `minOrNull` survive for
    /// +CallRewriteSequenceTerminals.swift and must stay out of both sets.
    @Test
    func sortExtremaNamesAreGoneExceptVirtualOnlySorted() {
        let (policy, lookup, _) = Self.makePolicy()
        #expect(!policy.sharedAggregateNames.contains(lookup.sortedName))
        #expect(policy.virtualOnlyAggregateNames.contains(lookup.sortedName))
        for name in [lookup.maxName, lookup.maxOrNullName, lookup.minOrNullName] {
            #expect(!policy.sharedAggregateNames.contains(name))
            #expect(!policy.virtualOnlyAggregateNames.contains(name))
        }
        // `minByOrNull` / `maxByOrNull` are gone too: RF-LOWER-CALL-012
        // deleted both their lookup-table properties and their only
        // downstream rewrite, so naming them here would not compile.
    }

    /// RF-LOWER-CALL-013: `directArrayConversionNames` now holds only `size`
    /// and `toList` — the array-literal-tracked direct-call side of the
    /// asymmetry `arrayConversionSetsDifferBetweenDirectAndVirtualCalls`
    /// used to describe. `sliceArray`/`reversedArray`/`asList`/`toTypedArray`
    /// and their `virtualArrayConversionNames` counterpart are gone: no
    /// Lowering rewrite has checked those names since KSP-1516 (and their
    /// lookup-table properties were deleted with the two rewrite files that
    /// used to read them), so protecting them here guarded nothing.
    /// `toList` keeps reaching the virtual side through
    /// `virtualOnlyAggregateNames` instead of an array-specific set, since it
    /// is also the Range/progression `toList` consumer.
    @Test
    func directArrayConversionNamesAreSizeAndToListOnly() {
        let (policy, lookup, _) = Self.makePolicy()
        #expect(policy.directArrayConversionNames == [lookup.sizeName, lookup.toListName])
        #expect(policy.virtualOnlyAggregateNames.contains(lookup.toListName))
    }

    // MARK: - direct-call decisions

    /// Only `.sourceBacked` preserves. The three other states each used to be a
    /// separate `guard` that fell through to the same `return false`.
    @Test
    func directCallPreservesOnlySourceBackedResolutions() {
        let (policy, lookup, _) = Self.makePolicy()
        let states: [SourceBackedCalleeResolution: Bool] = [
            .sourceBacked: true,
            .externalBridge: false,
            .unresolved: false,
            .unknownSymbol: false,
        ]
        for (resolution, expected) in states {
            let preserved = policy.preservesDirectCall(
                callee: lookup.groupByName,
                resolution: resolution,
                receiverIsTrackedArrayLiteral: false,
                receiverIsTrackedRuntimeSequence: false,
                calleeHasSequenceReceiverType: false
            )
            #expect(preserved == expected, "\(resolution) should preserve == \(expected)")
        }
    }

    /// A virtual-only name reaching the direct path is not preserved. `chunked`
    /// on a range is the live example: it arrives as virtual dispatch, and the
    /// direct predicate never listed it.
    @Test
    func directCallDoesNotPreserveVirtualOnlyNames() {
        let (policy, _, interner) = Self.makePolicy()
        for name in ["chunked", "windowed", "average", "isEmpty", "random", "fold", "reduce"] {
            #expect(
                !policy.preservesDirectCall(
                    callee: interner.intern(name),
                    resolution: .sourceBacked,
                    receiverIsTrackedArrayLiteral: false,
                    receiverIsTrackedRuntimeSequence: false,
                    calleeHasSequenceReceiverType: false
                ),
                "\(name) is virtual-only"
            )
            #expect(
                policy.preservesVirtualCall(
                    callee: interner.intern(name),
                    resolution: .sourceBacked,
                    receiverArrayClassName: { nil }
                ),
                "\(name) must still be preserved on virtual dispatch"
            )
        }
    }

    /// `size` is preserved on the direct path only while the receiver is an
    /// array expression the pre-scan tracked. It is not in the shared set, so
    /// an untracked receiver falls through to `false`.
    @Test
    func directArrayConversionRequiresATrackedArrayReceiver() {
        let (policy, lookup, _) = Self.makePolicy()
        #expect(
            policy.preservesDirectCall(
                callee: lookup.sizeName,
                resolution: .sourceBacked,
                receiverIsTrackedArrayLiteral: true,
                receiverIsTrackedRuntimeSequence: false,
                calleeHasSequenceReceiverType: false
            )
        )
        #expect(
            !policy.preservesDirectCall(
                callee: lookup.sizeName,
                resolution: .sourceBacked,
                receiverIsTrackedArrayLiteral: false,
                receiverIsTrackedRuntimeSequence: false,
                calleeHasSequenceReceiverType: false
            ),
            "size is not in the shared set, so an untracked receiver must fall through"
        )
        #expect(
            !policy.preservesDirectCall(
                callee: lookup.sizeName,
                resolution: .externalBridge,
                receiverIsTrackedArrayLiteral: true,
                receiverIsTrackedRuntimeSequence: false,
                calleeHasSequenceReceiverType: false
            ),
            "a tracked array receiver does not preserve a synthetic callee"
        )
    }

    /// STDLIB-pipeline §5 / KSP-441: `map`/`filter` on a runtime Sequence must
    /// keep going through `kk_sequence_*`, whether the receiver is a tracked
    /// `RuntimeSequenceBox` or merely `Sequence`-typed. RF-LOWER-CALL-014 owns
    /// replacing these two exceptions; until then they must not drift.
    @Test
    func directCallKeepsBothSequenceRuntimeRepresentationExceptions() {
        let (policy, lookup, _) = Self.makePolicy()
        for callee in [lookup.mapName, lookup.filterName] {
            #expect(
                !policy.preservesDirectCall(
                    callee: callee,
                    resolution: .sourceBacked,
                    receiverIsTrackedArrayLiteral: false,
                    receiverIsTrackedRuntimeSequence: true,
                    calleeHasSequenceReceiverType: false
                ),
                "tracked runtime sequence receiver must not be preserved"
            )
            #expect(
                !policy.preservesDirectCall(
                    callee: callee,
                    resolution: .sourceBacked,
                    receiverIsTrackedArrayLiteral: false,
                    receiverIsTrackedRuntimeSequence: false,
                    calleeHasSequenceReceiverType: true
                ),
                "a Sequence-typed receiver may still be a RuntimeSequenceBox"
            )
        }
    }

    /// The exceptions are scoped to `map`/`filter`. `flatMap` traverses the
    /// receiver through the shared iterator bridge, so a Sequence receiver does
    /// not disqualify it.
    @Test
    func directCallSequenceExceptionsDoNotCoverFlatMapOrGroupBy() {
        let (policy, lookup, _) = Self.makePolicy()
        for callee in [lookup.flatMapName, lookup.flatMapIndexedName, lookup.groupByName] {
            #expect(
                policy.preservesDirectCall(
                    callee: callee,
                    resolution: .sourceBacked,
                    receiverIsTrackedArrayLiteral: false,
                    receiverIsTrackedRuntimeSequence: true,
                    calleeHasSequenceReceiverType: true
                )
            )
        }
    }

    // MARK: - virtual-call decisions

    /// The virtual array branches answer with receiver-class membership once
    /// the class resolves, and fall through when it does not. `size` on a
    /// `List` receiver therefore stays rewritable.
    @Test
    func virtualArraySizeAnswersByReceiverClass() {
        let (policy, lookup, _) = Self.makePolicy()
        #expect(
            policy.preservesVirtualCall(
                callee: lookup.sizeName,
                resolution: .sourceBacked,
                receiverArrayClassName: { "IntArray" }
            )
        )
        #expect(
            !policy.preservesVirtualCall(
                callee: lookup.sizeName,
                resolution: .sourceBacked,
                receiverArrayClassName: { "List" }
            ),
            "a non-array receiver keeps the generic runtime bridge"
        )
        #expect(
            !policy.preservesVirtualCall(
                callee: lookup.sizeName,
                resolution: .sourceBacked,
                receiverArrayClassName: { nil }
            ),
            "an unresolved receiver class falls through; size is in neither API set"
        )
    }

    /// Every array class the `size` branch accepts, including the unsigned
    /// arrays and generic `Array`. RF-LOWER-CALL-013 removed
    /// `virtualArrayConversionNames` (the array-conversion-member branch that
    /// used to share `arrayReceiverTypeNames` with `size`), so `size` is now
    /// this set's only consumer.
    @Test
    func virtualSizeAcceptsEveryArrayReceiverClass() {
        let (policy, lookup, _) = Self.makePolicy()
        let expected: Set<String> = [
            "IntArray", "LongArray", "ShortArray", "ByteArray",
            "CharArray", "BooleanArray", "DoubleArray", "FloatArray",
            "UByteArray", "UShortArray", "UIntArray", "ULongArray", "Array",
        ]
        #expect(policy.arrayReceiverTypeNames == expected)
        for className in expected {
            #expect(
                policy.preservesVirtualCall(
                    callee: lookup.sizeName,
                    resolution: .sourceBacked,
                    receiverArrayClassName: { className }
                ),
                "\(className).size must keep its Kotlin declaration"
            )
        }
    }

    /// Virtual dispatch has no Sequence exception of its own — runtime-backed
    /// Sequence receivers are handled by `rewriteSequenceVirtualCall`. Pinning
    /// this keeps RF-LOWER-CALL-014 from assuming the exception lives in two
    /// places.
    @Test
    func virtualCallHasNoSequenceException() {
        let (policy, lookup, _) = Self.makePolicy()
        for callee in [lookup.mapName, lookup.filterName] {
            #expect(
                policy.preservesVirtualCall(
                    callee: callee,
                    resolution: .sourceBacked,
                    receiverArrayClassName: { nil }
                )
            )
        }
    }

    /// Same resolution gate as the direct path.
    @Test
    func virtualCallPreservesOnlySourceBackedResolutions() {
        let (policy, lookup, _) = Self.makePolicy()
        for resolution: SourceBackedCalleeResolution in [.externalBridge, .unresolved, .unknownSymbol] {
            #expect(
                !policy.preservesVirtualCall(
                    callee: lookup.sortedName,
                    resolution: resolution,
                    receiverArrayClassName: { nil }
                ),
                "\(resolution) must not preserve"
            )
        }
    }

    // MARK: - production path

    /// A user function that merely shares a preserved API name must survive the
    /// pass. It resolves to a declaration with a source site, so the policy
    /// preserves it for exactly the same reason it preserves a migrated stdlib
    /// declaration — no name-based exception is involved.
    @Test
    func userFunctionSharingAPreservedNameSurvivesLowering() throws {
        let source = """
        fun flatten(x: Int): Int = x + 1

        class Bag(val items: List<Int>)

        fun Bag.count(): Int = items.size + 100

        fun main() {
            println(flatten(41))
            println(Bag(listOf(1, 2)).count())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "SourceBackedPreservationShadowing",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let kirCtx = KIRContext(
                diagnostics: ctx.diagnostics,
                options: ctx.options,
                interner: ctx.interner,
                sema: ctx.sema
            )
            module.scanFeatures()
            try CollectionLiteralLoweringPass().run(module: module, ctx: kirCtx)

            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            // A rewrite replaces the callee outright, so the names surviving
            // here are proof the policy preserved both user declarations.
            #expect(callees.contains("flatten"), "callees: \(callees)")
            #expect(callees.contains("count"), "callees: \(callees)")
        }
    }
}
#endif
