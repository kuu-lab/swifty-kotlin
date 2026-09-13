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
/// chains agreed on 91 API names and diverged on twenty more plus the shape of
/// the array-conversion check, and nothing in either file recorded which
/// divergences were deliberate. These tests fix both halves: the four callee
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
    func virtualOnlyNamesAreExactlyTheRangeAndRandomMembers() {
        let (policy, _, interner) = Self.makePolicy()
        let resolved = Set(policy.virtualOnlyAggregateNames.map { interner.resolve($0) })
        #expect(
            resolved == [
                // RF-LOWER-CALL-009 (#6762) left these eleven on the virtual
                // path only.
                "fold", "foldIndexed", "foldRight", "foldRightIndexed",
                "reduce", "reduceOrNull", "reduceRight", "reduceRightOrNull",
                "reduceRightIndexed", "reduceRightIndexedOrNull", "scanReduce",
                "isEmpty", "iterator",
                "toList", "toIntArray", "average", "chunked", "windowed",
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
    /// RF-LOWER-CALL-008 onwards must do deliberately.
    @Test
    func sharedAggregateNameCountMatchesTheExtractedPredicate() {
        let (policy, _, _) = Self.makePolicy()
        #expect(policy.sharedAggregateNames.count == 91, "got \(policy.sharedAggregateNames.count)")
    }

    /// The array-conversion asymmetry the old code left unsaid: the direct path
    /// keys on a tracked array *expression* and includes `size`/`toList`, while
    /// the virtual path keys on the receiver's static *type* and has neither —
    /// `toList` is reached there through `virtualOnlyAggregateNames` instead.
    @Test
    func arrayConversionSetsDifferBetweenDirectAndVirtualCalls() {
        let (policy, lookup, _) = Self.makePolicy()
        #expect(policy.directArrayConversionNames.contains(lookup.sizeName))
        #expect(policy.directArrayConversionNames.contains(lookup.toListName))
        #expect(!policy.virtualArrayConversionNames.contains(lookup.sizeName))
        #expect(!policy.virtualArrayConversionNames.contains(lookup.toListName))
        #expect(policy.virtualOnlyAggregateNames.contains(lookup.toListName))
        #expect(
            policy.virtualArrayConversionNames == [
                lookup.sliceArrayName, lookup.reversedArrayName,
                lookup.asListName, lookup.toTypedArrayName,
            ]
        )
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

    /// Every array class the branches accept, including the unsigned arrays and
    /// generic `Array`.
    @Test
    func virtualArrayConversionAcceptsEveryArrayReceiverClass() {
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
                    callee: lookup.asListName,
                    resolution: .sourceBacked,
                    receiverArrayClassName: { className }
                ),
                "\(className).asList must keep its Kotlin declaration"
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
