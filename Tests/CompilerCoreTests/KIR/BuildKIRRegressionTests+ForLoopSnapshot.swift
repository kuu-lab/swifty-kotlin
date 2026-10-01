#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    /// Reading a local yields its storage register, so a for-loop bound or
    /// iterable used directly would follow reassignment inside the body.
    /// Both must be copied into fresh temporaries before the loop.
    @Test func testBuildKIRSnapshotsForLoopRangeBoundAndArrayIterable() throws {
        let source = """
        fun rangeLoop(): Int {
            var n = 5
            for (i in 0..n) { n-- }
            return n
        }

        fun arrayLoop(): Int {
            var arr = intArrayOf(1, 2, 3)
            var sum = 0
            for (x in arr) { arr = intArrayOf(10, 20); sum += x }
            return sum
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        func copyTargets(_ body: [KIRInstruction]) -> Set<KIRExprID> {
            var targets = Set<KIRExprID>()
            for case let .copy(_, to) in body { targets.insert(to) }
            return targets
        }

        let rangeBody = try findKIRFunctionBody(named: "rangeLoop", in: module, interner: ctx.interner)
        let rangeTargets = copyTargets(rangeBody)
        var sawInductionCompare = false
        for case let .call(_, callee, arguments, _, _, _, _, _) in rangeBody
            where ctx.interner.resolve(callee) == "__kk_int_range_induction_le"
        {
            sawInductionCompare = true
            #expect(rangeTargets.contains(arguments[1]), "range upper bound must be a snapshot temporary, not the variable's storage")
        }
        #expect(sawInductionCompare)

        let arrayBody = try findKIRFunctionBody(named: "arrayLoop", in: module, interner: ctx.interner)
        let arrayTargets = copyTargets(arrayBody)
        var sawArrayGet = false
        for case let .call(_, callee, arguments, _, _, _, _, _) in arrayBody
            where ctx.interner.resolve(callee) == "kk_array_get_inbounds"
        {
            sawArrayGet = true
            #expect(arrayTargets.contains(arguments[0]), "iterated array must be a snapshot temporary, not the variable's storage")
        }
        #expect(sawArrayGet)
    }
}
#endif
