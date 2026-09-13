#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func iterableContainsDirectAndOperatorCallsUseBundledSource() throws {
        let source = """
        fun direct(values: Iterable<Int>, needle: Int): Boolean = values.contains(needle)
        fun operatorCall(values: Iterable<Int>, needle: Int): Boolean = needle in values
        fun negativeOperator(values: Iterable<Int>, needle: Int): Boolean = needle !in values
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected Iterable.contains KIR to build, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let module = try #require(ctx.kir)
        for functionName in ["direct", "operatorCall", "negativeOperator"] {
            let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))
            #expect(callees.contains("contains"), "Expected \(functionName) to call bundled Iterable.contains")
            #expect(!callees.contains("kk_op_contains"))
            #expect(!callees.contains("kk_sequence_contains"))
        }
    }

    @Test
    func erasedEqualityRegistersUserEqualsOverride() throws {
        // Regression note (BUG-244): this fixture must not be named `Key` (or
        // `Element`) — those simple names collide with imported nested stdlib
        // types (e.g. `kotlin.coroutines.CoroutineContext.Key`) and trip a
        // separate, pre-existing Sema bug where a bundled stdlib file's
        // supertype reference resolves to this test's top-level class instead
        // of its own file-scoped import. See TODO.md BUG-244.
        let source = """
        class ErasedEqKey(val id: Int, val ignored: Int) {
            override fun equals(other: Any?): Boolean = other is ErasedEqKey && id == other.id
            override fun hashCode(): Int = id
        }

        fun <T> same(lhs: T, rhs: T): Boolean = lhs == rhs
        fun compareKeys(): Boolean = same(ErasedEqKey(7, 1), ErasedEqKey(7, 2))
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected erased equality KIR to build, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let module = try #require(ctx.kir)
        let genericBody = try findKIRFunctionBody(named: "same", in: module, interner: ctx.interner)
        #expect(genericBody.contains { instruction in
            guard case let .binary(op, _, _, _) = instruction else { return false }
            return op == .equal
        })

        let callerBody = try findKIRFunctionBody(named: "compareKeys", in: module, interner: ctx.interner)
        let callerCallees = extractCallees(from: callerBody, interner: ctx.interner)
        #expect(callerCallees.filter { $0 == "kk_object_register_equals_override" }.count == 2)
    }
}
#endif
