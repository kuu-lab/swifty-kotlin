#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// RF-LOWER-CALL-009: pin the source-preservation contract of the List
/// fold / reduce / scan / running family.
///
/// `shouldPreserveSourceBackedAggregateCall` used to name all nineteen
/// accumulation callees, but eleven of them had nothing left to short-circuit:
/// the legacy `kk_list_fold*` / `kk_list_scan*` bridges are no longer emitted
/// anywhere (they survive only as `RuntimeABISpec` entries), and Sequence /
/// Range accumulation routing happens in `CallLowerer`, which hands the pass an
/// already-`kk_`-named callee.  Removing an inert allowlist entry is invisible
/// today but would stop being invisible the moment a new rewrite branch claimed
/// one of those names, so the contract is asserted here directly instead of
/// resting on the absence of a rewrite.
///
/// The eight `sequenceExprIDs`-gated names stay in the allowlist: whether a
/// source-backed declaration with a RuntimeSequenceBox receiver should be
/// redirected is the KSP-441 question RF-LOWER-CALL-014 owns.  They are pinned
/// here too, so that task changes them deliberately rather than by accident.
@Suite
struct ListAccumulationSourcePreservationTests {
    /// The eleven callees RF-LOWER-CALL-009 dropped from the preserve allowlist.
    private static let unguardedAccumulationCallees: Set<String> = [
        "fold", "foldIndexed", "foldRight", "foldRightIndexed",
        "reduce", "reduceOrNull",
        "reduceRight", "reduceRightOrNull",
        "reduceRightIndexed", "reduceRightIndexedOrNull",
        "scanReduce",
    ]

    /// The eight callees still short-circuited, for RF-LOWER-CALL-014.
    private static let guardedAccumulationCallees: Set<String> = [
        "scan", "scanIndexed",
        "runningFold", "runningFoldIndexed",
        "runningReduce", "runningReduceIndexed",
        "reduceIndexed", "reduceIndexedOrNull",
    ]

    /// Every accumulation callee, on a literal `List<Int>` receiver.
    private static let listAccumulationSource = """
    fun main() {
        val xs = listOf(1, 2, 3, 4)
        val a = xs.fold(0) { acc, v -> acc + v }
        val b = xs.foldIndexed(0) { i, acc, v -> acc + i + v }
        val c = xs.foldRight(0) { v, acc -> acc + v }
        val d = xs.foldRightIndexed(0) { i, v, acc -> acc + i + v }
        val e = xs.reduce { acc, v -> acc + v }
        val f = xs.reduceOrNull { acc, v -> acc + v }
        val g = xs.reduceRight { v, acc -> v + acc }
        val h = xs.reduceRightOrNull { v, acc -> v + acc }
        val i = xs.reduceRightIndexed { idx, v, acc -> acc + idx + v }
        val j = xs.reduceRightIndexedOrNull { idx, v, acc -> acc + idx + v }
        val k = xs.scanReduce { acc, v -> acc + v }
        val l = xs.scan(0) { acc, v -> acc + v }
        val m = xs.scanIndexed(0) { i2, acc, v -> acc + i2 + v }
        val n = xs.runningFold(0) { acc, v -> acc + v }
        val o = xs.runningFoldIndexed(0) { i2, acc, v -> acc + i2 + v }
        val p = xs.runningReduce { acc, v -> acc + v }
        val q = xs.runningReduceIndexed { i2, acc, v -> acc + i2 + v }
        val r = xs.reduceIndexed { i2, acc, v -> acc + i2 + v }
        val s = xs.reduceIndexedOrNull { i2, acc, v -> acc + i2 + v }
    }
    """

    /// The same family reached through a `List<Int>` parameter, so the receiver
    /// is not a tracked literal in `CollectionRewriteState`.
    private static let parameterReceiverSource = """
    fun viaParam(xs: List<Int>): Int {
        val a = xs.fold(0) { acc, v -> acc + v }
        val b = xs.foldIndexed(0) { i, acc, v -> acc + i + v }
        val c = xs.foldRight(0) { v, acc -> acc + v }
        val d = xs.foldRightIndexed(0) { i, v, acc -> acc + i + v }
        val e = xs.reduce { acc, v -> acc + v }
        val f = xs.reduceRight { v, acc -> v + acc }
        val g = xs.reduceRightIndexed { idx, v, acc -> acc + idx + v }
        val h = xs.scanReduce { acc, v -> acc + v }.size
        return a + b + c + d + e + f + g + h
    }

    fun main() {
        println(viaParam(listOf(1, 2, 3)))
    }
    """

    /// Run the lowering pass under test, and nothing after it, so a redirect
    /// cannot be masked by a later pass.
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

    /// `.call` instructions in `body` whose callee is an accumulation name,
    /// with the resolved symbol so a dropped symbol is caught too.
    private static func accumulationCalls(
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> [(callee: String, symbol: SymbolID?)] {
        body.compactMap { instruction in
            guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else { return nil }
            let name = interner.resolve(callee)
            guard unguardedAccumulationCallees.contains(name)
                || guardedAccumulationCallees.contains(name)
            else { return nil }
            return (name, symbol)
        }
    }

    private static func loweredBody(
        of source: String,
        function: String,
        moduleName: String
    ) throws -> (body: [KIRInstruction], interner: StringInterner) {
        var captured: ([KIRInstruction], StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: moduleName,
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: function, in: module, interner: ctx.interner)
            captured = (body, ctx.interner)
        }
        return try #require(captured)
    }

    // MARK: - the eleven names dropped from the allowlist

    /// Each of the eleven survives the pass as a resolved source call.  If a
    /// future rewrite branch claims one of these names, this fails instead of
    /// silently redirecting a bundled Kotlin declaration to a runtime bridge.
    @Test
    func listAccumulationCallsKeepTheirSourceDeclaration() throws {
        let (body, interner) = try Self.loweredBody(
            of: Self.listAccumulationSource,
            function: "main",
            moduleName: "ListAccumulationPreserve"
        )
        let calls = Self.accumulationCalls(in: body, interner: interner)

        let survivors = Set(calls.map(\.callee))
        #expect(
            survivors == Self.unguardedAccumulationCallees.union(Self.guardedAccumulationCallees),
            "missing: \(Self.unguardedAccumulationCallees.union(Self.guardedAccumulationCallees).subtracting(survivors))"
        )

        // A preserved call keeps the symbol Sema selected; a rewrite emits
        // `symbol: nil` with a `kk_*` callee.
        for call in calls {
            #expect(call.symbol != nil, "\(call.callee) lost its resolved symbol")
        }
    }

    /// No accumulation call is redirected to a runtime bridge.  Matched by
    /// prefix so both the `kk_list_*` legacy names and any `kk_sequence_*`
    /// redirect are caught.
    @Test
    func listAccumulationCallsAreNotRedirectedToRuntimeBridges() throws {
        let (body, interner) = try Self.loweredBody(
            of: Self.listAccumulationSource,
            function: "main",
            moduleName: "ListAccumulationNoBridge"
        )
        let callees = extractCallees(from: body, interner: interner)

        let accumulationSuffixes = Self.unguardedAccumulationCallees
            .union(Self.guardedAccumulationCallees)
        let bridged = callees.filter { callee in
            guard callee.hasPrefix("kk_") || callee.hasPrefix("__kk_") else { return false }
            return accumulationSuffixes.contains { callee.hasSuffix("_\($0)") }
        }
        #expect(bridged.isEmpty, "redirected to runtime bridges: \(bridged)")
    }

    /// An untracked receiver (a `List<Int>` parameter rather than a literal)
    /// takes the same route, so the contract does not depend on
    /// `CollectionRewriteState` literal tracking.
    @Test
    func parameterReceiverAccumulationCallsKeepTheirSourceDeclaration() throws {
        let (body, interner) = try Self.loweredBody(
            of: Self.parameterReceiverSource,
            function: "viaParam",
            moduleName: "ListAccumulationParameterReceiver"
        )
        let calls = Self.accumulationCalls(in: body, interner: interner)

        let survivors = Set(calls.map(\.callee))
        #expect(
            survivors == [
                "fold", "foldIndexed", "foldRight", "foldRightIndexed",
                "reduce", "reduceRight", "reduceRightIndexed", "scanReduce",
            ],
            "survivors: \(survivors.sorted())"
        )
        for call in calls {
            #expect(call.symbol != nil, "\(call.callee) lost its resolved symbol")
        }
    }
}
#endif
