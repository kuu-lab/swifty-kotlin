#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BoxingIntegrationTests {
    @Test func testPairTripleBoxingSurgicalFix() throws {
        let source = """
        fun test() {
            val p = Pair(1, "one")
            val t = Triple(2, 3, "three")
            val p2 = 4 to "four"
        }
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module: KIRModule = try #require(ctx.kir)
        let testFunc: KIRFunction = try findKIRFunction(named: "test", in: module, interner: ctx.interner)

        let boxingCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_box_int"
            }
            return false
        }

        // We expect at least 4 boxing calls: 1 for Pair(1, ...), 2 for Triple(2, 3, ...), 1 for 4 to ...
        #expect(boxingCalls.count >= 4, "Should have boxed primitive arguments for Pair and Triple. Found \(boxingCalls.count)")
    }

    @Test func testMutableListAddBoxesPrimitiveElement() throws {
        let source = """
        fun test(list: MutableList<Int>) {
            list.add(1)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module: KIRModule = try #require(ctx.kir)
        let testFunc: KIRFunction = try findKIRFunction(named: "test", in: module, interner: ctx.interner)

        let boxingCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_box_int"
            }
            return false
        }

        // MutableList.add stores its argument verbatim into the backing element array,
        // whose element type is the erased type parameter E. A primitive element must
        // be boxed so it carries its concrete type at runtime — matching how
        // listOf(...) / mutableListOf(...) already box every element. Storing a raw
        // primitive breaks toString() for Char (prints the code point), Boolean
        // (false == 0 collides with the null sentinel) and Double/Float (the bit
        // pattern is misread as an Int). See
        // CodegenBackendIntegrationTests.testPrimitiveArgumentBoxedWhenAddedToMutableCollections.
        #expect(boxingCalls.count == 1, "MutableList.add should box its primitive argument. Found \(boxingCalls.count)")
    }

    @Test func testUntilInfixFunctionResultIsNotUnboxed() throws {
        let source = """
        fun test(): Boolean {
            return 10L in 10L until 20L
        }
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module: KIRModule = try #require(ctx.kir)
        let testFunc: KIRFunction = try findKIRFunction(named: "test", in: module, interner: ctx.interner)

        // `until` is registered with a scalar Long return type (matching the
        // isRangeExpr duck-typing convention used for range operators), but
        // kk_op_rangeUntil always returns a boxed RuntimeRangeBox reference at
        // runtime. Unlike `..`/`downTo`/`step`, the named `until` call carries a
        // resolved Sema symbol, so a naive return-type-driven ABI lowering pass
        // would unbox the range object itself as if it were a raw Long — see
        // kk_unbox_long in RuntimeBoxing.swift, which prints a diagnostic and
        // pollutes stdout when handed a non-LongBox object pointer.
        var rangeResults: Set<KIRExprID> = []
        for instruction in testFunc.body {
            if case let .call(_, callee, _, result, _, _, _, _) = instruction,
               ctx.interner.resolve(callee) == "kk_op_rangeUntil",
               let result
            {
                rangeResults.insert(result)
            }
        }
        #expect(!rangeResults.isEmpty, "Expected a kk_op_rangeUntil call in the lowered body")

        let erroneousUnboxCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, arguments, _, _, _, _, _) = instruction {
                let calleeName = ctx.interner.resolve(callee)
                return (calleeName == "kk_unbox_long" || calleeName == "kk_unbox_int")
                    && arguments.contains { rangeResults.contains($0) }
            }
            return false
        }
        #expect(
            erroneousUnboxCalls.isEmpty,
            "kk_op_rangeUntil's boxed range result must not be unboxed. Found \(erroneousUnboxCalls.count) offending call(s)"
        )
    }
}
#endif
