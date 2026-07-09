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

    @Test func testSequenceOfBoxesPrimitiveElements() throws {
        let source = """
        fun test() {
            val seq = sequenceOf(1, 2, 3)
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

        // sequenceOf(...) copies its elements verbatim into the same erased-to-Any
        // backing array as listOf(...)/setOf(...) (kk_sequence_of in
        // RuntimeSequence.swift stores RuntimeArrayBox.elements as-is into
        // RuntimeSequenceBox). Each primitive element must therefore be boxed so it
        // carries its concrete type at runtime, exactly like listOf/setOf already do.
        #expect(boxingCalls.count == 3, "sequenceOf should box each primitive element. Found \(boxingCalls.count)")
    }
}
#endif
