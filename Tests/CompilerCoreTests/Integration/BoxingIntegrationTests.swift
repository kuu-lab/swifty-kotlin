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

        let calleeNames = testFunc.body.compactMap { instruction -> String? in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee)
            }
            return nil
        }

        // arr[0] reads a boxed element back out of Array<Double>'s backing store.
        // Without unboxing here, the boxed pointer would be misread as a raw double
        // bit pattern the next time it crosses an Any boundary (e.g. println),
        // producing garbage — mirroring List.get's kk_list_get + kk_unbox_double.
        #expect(calleeNames.contains("kk_box_double"), "Construction must box each Double element.")
        #expect(calleeNames.contains("kk_unbox_double"), "arr[0] must unbox the element read back from Array<Double>.")
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

        // Construction boxes 2 elements (1.5, 2.5); arr[0] = 9.5 must box the
        // assigned value too, or the slot ends up holding a raw double bit pattern
        // that later boxed-aware reads (e.g. joinToString) misinterpret.
        #expect(boxingCalls.count == 3, "arr[0] = 9.5 should box the assigned value in addition to the 2 constructed elements. Found \(boxingCalls.count)")
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
}
#endif
