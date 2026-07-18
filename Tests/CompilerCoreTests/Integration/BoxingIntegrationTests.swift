#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite @MainActor
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

    @Test func testArrayOfBoxesPrimitiveElements() throws {
        let source = """
        fun test() {
            val arr = arrayOf(1, 2, 3)
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

        // arrayOf(...) shares its vararg-packing path with intArrayOf/charArrayOf/...,
        // which must keep storing raw primitives. Only the generic arrayOf<T> backs a
        // boxed Array<T> and needs each element boxed before kk_array_set, matching
        // listOf(...) / mutableListOf(...).
        #expect(boxingCalls.count == 3, "arrayOf(...) should box every primitive element. Found \(boxingCalls.count)")
    }

    @Test func testIntArrayOfDoesNotBoxElements() throws {
        let source = """
        fun test() {
            val arr = intArrayOf(1, 2, 3)
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

        // intArrayOf(...) shares "kk_array_of" external linkage with arrayOf<T>, but
        // its backing store (IntArray) holds raw primitives, not boxed Any — it must
        // not be boxed just because arrayOf<T> now is.
        #expect(boxingCalls.isEmpty, "intArrayOf(...) must not box its elements. Found \(boxingCalls.count)")
    }

    @Test func testArrayOfIndexedReadUnboxesElement() throws {
        let source = """
        fun test(): Double {
            val arr = arrayOf(1.5, 2.5)
            return arr[0]
        }
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module: KIRModule = try #require(ctx.kir)
        let testFunc: KIRFunction = try findKIRFunction(named: "test", in: module, interner: ctx.interner)

        let boxCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_box_double"
            }
            return false
        }
        let unboxCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_unbox_double"
            }
            return false
        }

        // Array<T>'s backing store holds boxed elements for primitive T (mirroring
        // listOf/kk_list_get). Reading an element must unbox right after the raw
        // kk_array_get, otherwise the boxed pointer gets misread as a raw value.
        #expect(!boxCalls.isEmpty, "Constructing arrayOf(1.5, 2.5) should box its elements. Found \(boxCalls.count)")
        #expect(!unboxCalls.isEmpty, "arr[0] on Array<Double> should unbox the read element. Found \(unboxCalls.count)")
    }

    @Test func testArrayOfIndexedAssignBoxesPrimitiveValue() throws {
        let source = """
        fun test() {
            val arr = arrayOf(1.5, 2.5)
            arr[0] = 9.5
        }
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module: KIRModule = try #require(ctx.kir)
        let testFunc: KIRFunction = try findKIRFunction(named: "test", in: module, interner: ctx.interner)

        let boxingCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_box_double"
            }
            return false
        }

        // 2 boxing calls for constructing arrayOf(1.5, 2.5), plus 1 more for the
        // assigned value 9.5 — without this, arr would end up with a mix of boxed
        // and raw elements, corrupting any later boxed-aware read.
        #expect(boxingCalls.count == 3, "arr[0] = 9.5 on Array<Double> should box the assigned value. Found \(boxingCalls.count)")
    }

    @Test func testIntArrayOfIndexedAssignDoesNotBoxValue() throws {
        let source = """
        fun test() {
            val arr = intArrayOf(1, 2)
            arr[0] = 9
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

        #expect(boxingCalls.isEmpty, "arr[0] = 9 on an IntArray must not box the assigned value. Found \(boxingCalls.count)")
    }

    @Test func testArrayOfBoxesNonSpreadElementsWhenMixedWithSpread() throws {
        let source = """
        fun test() {
            val other = arrayOf(10, 20)
            val arr = arrayOf(1, *other, 3)
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

        // Building `other` boxes its two literal elements (2 calls). Building `arr`
        // goes through the pairs-array/kk_vararg_spread_concat path because it mixes
        // a spread with plain elements; only the two non-spread literals (1, 3) must
        // be boxed there — the spread element is already an array handle and must
        // not be boxed again.
        #expect(
            boxingCalls.count == 4,
            "arrayOf(1, *other, 3) should box only its two non-spread literals (plus 2 for `other`). Found \(boxingCalls.count)"
        )
    }

    @Test func testCompoundAssignOnGenericArrayBoxesAndUnboxesUsingReceiverElementType() throws {
        let source = """
        fun test() {
            val arr = arrayOf(1L, 2L, 3L)
            arr[0] += 5L
        }
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module: KIRModule = try #require(ctx.kir)
        let testFunc: KIRFunction = try findKIRFunction(named: "test", in: module, interner: ctx.interner)

        let boxLongCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_box_long"
            }
            return false
        }
        let unboxLongCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_unbox_long"
            }
            return false
        }

        // arr[0] += 5L on an Array<Long> must unbox the read element and box the
        // stored result using the receiver's own element type (Long), derived from
        // Array<Long>'s type argument rather than heuristically re-derived from the
        // RHS expression — the two happen to agree here, but only the former stays
        // correct if the RHS were ever a different (compiler-permitted) numeric type.
        #expect(!boxLongCalls.isEmpty, "arr[0] += 5L on Array<Long> should box the result as Long. Found \(boxLongCalls.count)")
        #expect(!unboxLongCalls.isEmpty, "arr[0] += 5L on Array<Long> should unbox the read element as Long. Found \(unboxLongCalls.count)")
    }
}
#endif
