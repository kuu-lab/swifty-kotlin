#if canImport(Testing)
@testable import CompilerCore
import Testing

// `LoweringPhase` takes a `KIRModule.scanFeatures()` snapshot before the pass
// pipeline and several passes gate `shouldRun` on it. A pass that ran may have
// synthesized instructions the snapshot never saw, so the driver must
// invalidate the snapshot after each executed pass. Without that,
// `IntegerNarrowingPass` skipped modules whose only Int arithmetic was the
// `hashCode` synthesized by `DataEnumSealedSynthesisPass`, and
// `P(Int.MAX_VALUE, Int.MAX_VALUE).hashCode()` overflowed in 64 bits instead of
// wrapping to `-32` like kotlinc.
struct LoweringFeatureRescanTests {
    @Test
    func testIntegerNarrowingRunsForSynthesizedDataClassHashCode() throws {
        // No arithmetic operator anywhere in user code: the pre-pipeline scan
        // sees neither `.binary` instructions nor `kk_op_*` callees.
        let source = """
        data class P(val a: Int, val b: Int)

        fun main() {
            val p = P(2147483647, 2147483647)
            val h = p.hashCode()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "FeatureRescan",
                emit: .kirDump,
                includeStdlib: false
            )
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let mul = ctx.interner.intern("kk_op_mul")
            let narrow = ctx.interner.intern("kk_int_narrow")
            var sawSynthesizedMul = false
            var sawNarrowing = false
            for decl in module.arena.declarations {
                guard case let .function(function) = decl else { continue }
                for instruction in function.body {
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { continue }
                    if callee == mul { sawSynthesizedMul = true }
                    if callee == narrow { sawNarrowing = true }
                }
            }
            #expect(sawSynthesizedMul, "data class hashCode synthesis should emit kk_op_mul")
            #expect(
                sawNarrowing,
                Comment(rawValue: "IntegerNarrowingPass must narrow the synthesized hashCode arithmetic "
                    + "even though the pre-pipeline feature scan saw no arithmetic")
            )
        }
    }

    @Test
    func testInvalidateFeatureScanForcesRescan() {
        let interner = StringInterner()
        let arena = KIRArena()
        let (module, _) = makeModule(body: [.returnUnit], interner: interner, arena: arena)

        module.scanFeatures()
        #expect(module.usedCallees.isEmpty)

        let callee = interner.intern("kk_op_add")
        let result = arena.appendExpr(.temporary(0), type: TypeSystem().unitType)
        arena.transformFunctions { fn in
            var updated = fn
            updated.replaceBody(
                [
                    .call(symbol: nil, callee: callee, arguments: [], result: result, canThrow: false, thrownResult: nil),
                    .returnUnit,
                ],
                locations: [nil, nil]
            )
            return updated
        }

        module.ensureFeaturesScanned()
        #expect(!module.usedCallees.contains(callee), "ensureFeaturesScanned must not rescan while the snapshot is fresh")

        module.invalidateFeatureScan()
        module.ensureFeaturesScanned()
        #expect(module.usedCallees.contains(callee), "invalidateFeatureScan must make the next ensureFeaturesScanned rescan")
    }
}
#endif
