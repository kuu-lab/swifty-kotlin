@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.all))
struct RuntimeFunctionArityTests {
    private func functionToken(_ arity: Int, nullable: Bool = false) -> Int {
        Int((Int64(arity) << RuntimeTypeTokenEncoding.payloadShift)
            | RuntimeTypeTokenEncoding.functionBase
            | (nullable ? RuntimeTypeTokenEncoding.nullableBit : 0))
    }

    @Test(arguments: [0, 1, 2, 6, 22])
    func rawFunctionsMatchOnlyRegisteredArity(arity: Int) {
        let raw = 0x123400
        #expect(kk_op_is(raw, functionToken(arity)) == 0)
        #expect(kk_function_value_tag_arity(raw, arity) == raw)
        #expect(kk_op_is(raw, functionToken(arity)) == 1)
        #expect(kk_op_is(raw, functionToken(arity + 1)) == 0)
        #expect(kk_op_is(raw, functionToken(arity, nullable: true)) == 1)
        #expect(kk_op_safe_cast(raw, functionToken(arity)) == raw)
        #expect(kk_op_safe_cast(raw, functionToken(arity + 1)) == runtimeNullSentinelInt)
        #expect(kk_op_is(runtimeNullSentinelInt, functionToken(arity)) == 0)
        #expect(kk_op_is(runtimeNullSentinelInt, functionToken(arity, nullable: true)) == 1)
    }

    @Test func taggedCallableReferencesMatchFunctionArity() {
        let function = kk_callable_ref_tag_kfunction(0x234500, 0, 0, 2, 0)
        #expect(kk_op_is(function, functionToken(2)) == 1)
        #expect(kk_op_is(function, functionToken(1)) == 0)
        let property = kk_callable_ref_tag_kproperty(0x345600, 0, 0, 0)
        #expect(kk_op_is(property, functionToken(0)) == 0)
    }

    @Test func taggingPreservesRawInvocationAndCastIdentity() {
        let entry: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { a, b, _ in a + b }
        let raw = unsafeBitCast(entry, to: Int.self)
        let tagged = kk_function_value_tag_arity(raw, 2)
        var thrown = 0
        let cast = kk_op_cast(tagged, functionToken(2), &thrown)
        #expect(thrown == 0)
        #expect(cast == raw)
        #expect(kk_function_invoke_2(cast, 1, 2, &thrown) == 3)
        #expect(thrown == 0)
        _ = kk_op_cast(tagged, functionToken(1), &thrown)
        #expect(thrown != 0)
    }

    @Test func boxedFunctionsStillMatchTheirArity() {
        let boxed = kk_function_create_1(0x456700, 0, nil)
        #expect(kk_op_is(boxed, functionToken(1)) == 1)
        #expect(kk_op_is(boxed, functionToken(2)) == 0)
        let reflected = __kk_kfunction_create(0, 0x567800, 0, 2, 0, 0)
        #expect(kk_op_is(reflected, functionToken(2)) == 1)
        #expect(kk_op_is(reflected, functionToken(1)) == 0)
        #expect(kk_op_is(42, functionToken(1)) == 0)
    }
}
