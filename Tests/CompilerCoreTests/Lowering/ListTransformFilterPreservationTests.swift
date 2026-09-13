#if canImport(Testing)
@testable import CompilerCore
import Foundation
import RuntimeABI
import Testing

/// RF-LOWER-CALL-008: pin the *symbol-based* preservation of the List
/// transform/filter higher-order functions.
///
/// KSP-421 moved `map` / `mapIndexed` / `mapNotNull` / `mapIndexedNotNull` /
/// `flatMap` / `flatMapIndexed` / `flatten`, the `*To` destination variants and
/// the `filter` family to `Stdlib/kotlin/collections/ListHOF.kt` and deleted
/// every `kotlin.collections.List` entry from `StdlibSurfaceSpec`.  Lowering
/// kept protecting those calls through a name allowlist in
/// `shouldPreserveSourceBackedAggregateCall`, while the rewrite branches they
/// guarded could no longer fire — `collectionHOFRuntimeName(ownerKind: .list,
/// ...)` had nothing left to return.  RF-LOWER-CALL-008 removed both sides, so
/// the resolved Kotlin declaration now survives because nothing claims it.
///
/// These tests keep that reasoning falsifiable: `listHOFSurfaceHasNoTransformOrFilterEntry`
/// fails the moment a `.list` runtime link reappears for one of these names
/// (which would silently resurrect a rewrite the deleted branches used to
/// perform), and `sharedTransformNamesStayPreservedForMapReceivers` fails if
/// the retained `map` / `filter` / `flatMap` allowlist entries — which still
/// shield the Map receiver rewrite (`kk_map_*`) — are dropped as well.
@Suite
struct ListTransformFilterPreservationTests {
    /// The List transform/filter member names RF-LOWER-CALL-008 covers.
    private static let listTransformFilterNames = [
        "map", "mapIndexed", "mapNotNull", "mapIndexedNotNull",
        "mapTo", "mapIndexedTo", "mapNotNullTo", "mapIndexedNotNullTo",
        "flatMap", "flatMapIndexed", "flatMapTo", "flatMapIndexedTo", "flatten",
        "filter", "filterNot", "filterNotNull", "filterIndexed",
    ]

    /// The two `kk_*` prefixes below are the only hardcoded runtime-name
    /// literals this file needs, and they are deliberate: the metric they move
    /// (`loc_report.sh kk_literal_count`) tracks hardcoded bridge names, but a
    /// test whose whole point is "no such bridge is emitted" cannot derive them
    /// from a surface spec that no longer has the entries.
    private static let listRuntimePrefix = "kk_list_"
    private static let mapRuntimePrefix = "kk_map_"

    /// Runtime callees the deleted branches used to substitute.  `kk_list_of`
    /// (the literal factory) is deliberately excluded: it must keep firing.
    private static func isListTransformRuntimeCallee(_ name: String) -> Bool {
        let stripped = name.hasPrefix("__") ? String(name.dropFirst(2)) : name
        guard stripped.hasPrefix(listRuntimePrefix) else { return false }
        let member = String(stripped.dropFirst(listRuntimePrefix.count))
        return listTransformFilterNames.contains { member == $0 || member.hasPrefix($0) }
    }

    private static func runCollectionLiteralPassOnly(_ ctx: CompilationContext) throws -> KIRModule {
        let module = try #require(ctx.kir)
        let kirCtx = KIRContext(
            diagnostics: ctx.diagnostics,
            options: ctx.options,
            interner: ctx.interner,
            sema: ctx.sema
        )
        module.scanFeatures()
        try CollectionLiteralLoweringPass().run(module: module, ctx: kirCtx)
        return module
    }

    /// Every `.call` in `body` named `name`, with its resolved symbol.
    private static func calls(
        named name: String,
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> [(argumentCount: Int, symbol: SymbolID?)] {
        body.compactMap { instruction in
            guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction,
                  interner.resolve(callee) == name
            else { return nil }
            return (arguments.count, symbol)
        }
    }

    // MARK: - the precondition that makes the deleted rewrites unreachable

    /// The deletion in `+CallRewriteHOFTransforms.swift` /
    /// `+CallRewriteHandlers.swift` rests on `StdlibSurfaceSpec` carrying no
    /// `kotlin.collections.List` runtime link for these names.  Re-adding one
    /// would mean the List rewrite is wanted again, and this test is the place
    /// that says so.
    @Test
    func listHOFSurfaceHasNoTransformOrFilterEntry() {
        for name in Self.listTransformFilterNames {
            let specs = StdlibSurfaceSpec.collectionHOFSpecs(ownerKind: .list, memberName: name)
            #expect(
                specs.isEmpty,
                """
                List.\(name) regained a runtime surface spec \
                (\(specs.map(\.runtimeLinkName))); RF-LOWER-CALL-008 removed the \
                lowering branch that consumed it
                """
            )
        }
    }

    /// No synthetic stub may shadow the bundled declarations either: a synthetic
    /// symbol is not source-backed, so it would bypass the preservation path
    /// entirely and be lowered through its `externalLinkName`.
    ///
    /// Both fully-qualified shapes are checked, because the two producers differ:
    /// `HeaderHelpers+SyntheticListTransformMembers.swift` registers *members*
    /// under `kotlin.collections.List.<name>`, while `ListHOF.kt` / `Iterables.kt`
    /// declare *extensions* under `kotlin.collections.<name>`. The non-empty
    /// assertion is the positive control: without it, a wrong prefix would make
    /// the synthetic check pass by looking at nothing.
    @Test
    func bundledStdlibLeavesNoSyntheticListTransformOverload() throws {
        try withTemporaryFile(contents: "fun main() { val xs = listOf(1, 2).map { it * 2 } }") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ListTransformSyntheticSurface",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let collectionsFQName = ["kotlin", "collections"].map(ctx.interner.intern)
            let listFQName = collectionsFQName + [ctx.interner.intern("List")]
            for name in Self.listTransformFilterNames {
                let memberName = ctx.interner.intern(name)
                let candidates = sema.symbols.lookupAll(fqName: listFQName + [memberName])
                    + sema.symbols.lookupAll(fqName: collectionsFQName + [memberName])
                #expect(
                    !candidates.isEmpty,
                    """
                    \(name): neither kotlin.collections.List.\(name) nor \
                    kotlin.collections.\(name) resolves, so the synthetic check \
                    below would be vacuous
                    """
                )
                let synthetic = candidates
                    .filter { sema.symbols.symbol($0)?.flags.contains(.synthetic) == true }
                #expect(
                    synthetic.isEmpty,
                    "\(name) must have no synthetic overload alongside the bundled stdlib"
                )
            }
        }
    }

    // MARK: - representative shapes keep their resolved declaration

    /// 通常 / indexed / nullable 要素 / 捕捉 lambda / destination (`*To`) shapes.
    /// Each entry is (case label, callee name, Kotlin statement).
    private static let representativeShapes: [(label: String, callee: String, statement: String)] = [
        ("plain", "map", "val plain = listOf(1, 2, 3).map { it * 2 }"),
        ("capturing", "map", "val bias = 10; val captured = listOf(1, 2, 3).map { it + bias }"),
        ("indexed", "mapIndexed", "val indexed = listOf(1, 2, 3).mapIndexed { i, v -> i + v }"),
        (
            "indexedNotNull",
            "mapIndexedNotNull",
            "val indexedNotNull = listOf(1, 2, 3).mapIndexedNotNull { i, v -> if (i == 0) null else i + v }"
        ),
        ("nullableElements", "mapNotNull", "val nullableElements = listOf(1, null, 3).mapNotNull { it }"),
        ("filterNotNull", "filterNotNull", "val kept = listOf(1, null, 3).filterNotNull()"),
        ("flatMap", "flatMap", "val flat = listOf(1, 2).flatMap { listOf(it, it) }"),
        ("flatMapIndexed", "flatMapIndexed", "val flatIndexed = listOf(1, 2).flatMapIndexed { i, v -> listOf(i, v) }"),
        ("flatten", "flatten", "val flattened = listOf(listOf(1, 2), listOf(3)).flatten()"),
        ("filter", "filter", "val positive = listOf(1, 2, 3).filter { it > 1 }"),
        ("filterNot", "filterNot", "val notPositive = listOf(1, 2, 3).filterNot { it > 1 }"),
        ("filterIndexed", "filterIndexed", "val tail = listOf(1, 2, 3).filterIndexed { i, _ -> i > 0 }"),
        ("mapTo", "mapTo", "val dest = listOf(1, 2).mapTo(mutableListOf<Int>()) { it * 2 }"),
        (
            "mapIndexedTo",
            "mapIndexedTo",
            "val destIndexed = listOf(1, 2).mapIndexedTo(mutableListOf<Int>()) { i, v -> i + v }"
        ),
        (
            "mapNotNullTo",
            "mapNotNullTo",
            "val destNotNull = listOf(1, null).mapNotNullTo(mutableListOf<Int>()) { it }"
        ),
        (
            "flatMapTo",
            "flatMapTo",
            "val destFlat = listOf(1, 2).flatMapTo(mutableListOf<Int>()) { listOf(it) }"
        ),
    ]

    /// The call keeps its resolved symbol and no `kk_list_<transform>` callee
    /// appears, on the production source path.
    @Test(arguments: representativeShapes)
    func listTransformFilterCallsSurviveCollectionLiteralLowering(
        shape: (label: String, callee: String, statement: String)
    ) throws {
        try withTemporaryFile(contents: "fun main() { \(shape.statement) }") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ListTransformPreserve\(shape.label)",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(shape.label) diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            let preserved = Self.calls(named: shape.callee, in: body, interner: ctx.interner)
            #expect(
                !preserved.isEmpty,
                "\(shape.label): `\(shape.callee)` must stay a source call; callees: \(callees)"
            )
            let rewritten = callees.filter(Self.isListTransformRuntimeCallee)
            #expect(
                rewritten.isEmpty,
                "\(shape.label): lowering must not redirect to a List transform runtime bridge; got \(rewritten)"
            )

            let sema = try #require(ctx.sema)
            for call in preserved {
                let symbolID = try #require(
                    call.symbol,
                    "\(shape.label): the preserved call must carry a resolved symbol"
                )
                #expect(
                    sema.symbols.isSourceBackedSymbol(symbolID),
                    "\(shape.label): `\(shape.callee)` must resolve to a source-backed declaration"
                )
                #expect(
                    sema.symbols.symbol(symbolID)?.flags.contains(.synthetic) != true,
                    "\(shape.label): `\(shape.callee)` must not resolve to a synthetic stub"
                )
                #expect(
                    sema.symbols.externalLinkName(for: symbolID) == nil,
                    "\(shape.label): `\(shape.callee)` must not carry an external link name"
                )
                let fileID = try #require(
                    sema.symbols.sourceFileID(for: symbolID),
                    "\(shape.label): missing source file for `\(shape.callee)`"
                )
                let sourcePath = ctx.sourceManager.path(of: fileID)
                #expect(
                    sourcePath.hasPrefix("__bundled_kotlin/"),
                    "\(shape.label): `\(shape.callee)` must come from the bundled stdlib; got \(sourcePath)"
                )
            }
        }
    }

    // MARK: - the retained allowlist names are load-bearing

    /// `map` / `filter` / `flatMap` stayed in
    /// `shouldPreserveSourceBackedAggregateCall` because the same interned name
    /// also selects the Map receiver rewrite in `+CallRewriteHandlers.swift`
    /// (`kk_map_map`, `kk_map_filter`, `kk_map_flatMap`).  Dropping them for the
    /// List family would hand the source-backed Map declarations to that
    /// rewrite — RF-LOWER-CALL-012's territory, not this task's.
    @Test(arguments: [
        ("map", "val mapped = mapOf(1 to \"a\").map { (k, v) -> \"$k$v\" }"),
        ("filter", "val kept = mapOf(1 to \"a\").filter { it.key > 0 }"),
        ("flatMap", "val flat = mapOf(1 to \"a\").flatMap { listOf(it.key) }"),
    ])
    func sharedTransformNamesStayPreservedForMapReceivers(
        shape: (callee: String, statement: String)
    ) throws {
        try withTemporaryFile(contents: "fun main() { \(shape.statement) }") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapReceiverPreserve\(shape.callee)",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(shape.callee) diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                !Self.calls(named: shape.callee, in: body, interner: ctx.interner).isEmpty,
                "Map.\(shape.callee) must stay a source call; callees: \(callees)"
            )
            #expect(
                !callees.contains(Self.mapRuntimePrefix + shape.callee),
                "Map.\(shape.callee) must not be handed to the runtime bridge; callees: \(callees)"
            )
        }
    }
}
#endif
