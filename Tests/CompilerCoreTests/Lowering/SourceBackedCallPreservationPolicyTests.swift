#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

/// RF-LOWER-CALL-015: source-backed preservation is a resolution decision, not
/// a second list of migrated API names. Runtime Sequence boxes are the only
/// representation-specific exception; collection intrinsics are emitted under
/// their ABI callee before this policy is consulted.
@Suite
struct SourceBackedCallPreservationPolicyTests {
    private static func makePolicy() -> SourceBackedCallPreservationPolicy {
        SourceBackedCallPreservationPolicy()
    }

    // MARK: - callee resolution

    @Test
    func nilSymbolIsUnresolved() {
        let (sema, _, _, _) = makeSemaModule()
        #expect(SourceBackedCalleeResolution(symbol: nil, sema: sema) == .unresolved)
    }

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

    @Test
    func symbolIDWithoutTableEntryIsUnknownSymbol() {
        let (sema, _, _, _) = makeSemaModule()
        let bogus = SymbolID(rawValue: 999_999)
        #expect(sema.symbols.symbol(bogus) == nil)
        #expect(SourceBackedCalleeResolution(symbol: bogus, sema: sema) == .unknownSymbol)
    }

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

    // MARK: - policy

    @Test
    func onlySourceBackedDeclarationsCanBePreserved() {
        let policy = Self.makePolicy()
        for resolution in [
            SourceBackedCalleeResolution.unresolved,
            .unknownSymbol,
            .externalBridge,
        ] {
            #expect(
                !policy.preserves(
                    resolution: resolution,
                    sequenceRuntimeRepresentation: .notSequence
                ),
                "\(resolution) must remain eligible for a runtime rewrite"
            )
        }
        #expect(
            policy.preserves(
                resolution: .sourceBacked,
                sequenceRuntimeRepresentation: .notSequence
            )
        )
    }

    @Test
    func sourceBackedDeclarationUsesRuntimeRepresentationEvidence() {
        let policy = Self.makePolicy()
        #expect(
            policy.preserves(
                resolution: .sourceBacked,
                sequenceRuntimeRepresentation: .sourceObject
            )
        )
        #expect(
            policy.preserves(
                resolution: .sourceBacked,
                sequenceRuntimeRepresentation: .notSequence
            )
        )
        #expect(
            !policy.preserves(
                resolution: .sourceBacked,
                sequenceRuntimeRepresentation: .runtimeBox
            )
        )
        #expect(
            !policy.preserves(
                resolution: .sourceBacked,
                sequenceRuntimeRepresentation: .unknown
            ),
            "an unclassified Sequence receiver must remain available to bridge routing"
        )
    }

    // MARK: - production path

    /// A user declaration can share a migrated stdlib name without being
    /// redirected to a runtime entry point. The direct and virtual call entry
    /// points both use the same resolution-based policy.
    @Test
    func userFunctionsSharingMigratedNamesSurviveLowering() throws {
        let source = """
        fun flatten(x: Int): Int = x + 1
        fun map(sequence: Sequence<Int>): Int = 42

        class Bag(val items: List<Int>)

        fun Bag.count(): Int = items.size + 100

        fun main() {
            println(flatten(41))
            println(map(sequenceOf(1)))
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
            #expect(callees.contains("flatten"), "callees: \(callees)")
            #expect(callees.contains("map"), "callees: \(callees)")
            #expect(callees.contains("count"), "callees: \(callees)")
        }
    }
}
#endif
