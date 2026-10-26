@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.all))
struct RuntimeFunctionArityTests {
    private func functionToken(_ arity: Int, nullable: Bool = false, suspend: Bool = false) -> Int {
        let payload = Int64(arity) | (suspend ? 0x100 : 0)
        return Int((payload << RuntimeTypeTokenEncoding.payloadShift)
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

    @Test func suspendFunctionsMatchTheirSuspendTypeAndLoweredFunctionShape() {
        let suspendRaw = 0x123500
        let plainRaw = 0x123600
        _ = kk_function_value_tag_arity(suspendRaw, 0x100)
        _ = kk_function_value_tag_arity(plainRaw, 0)

        #expect(kk_op_is(suspendRaw, functionToken(0, suspend: true)) == 1)
        #expect(kk_op_is(suspendRaw, functionToken(0)) == 0)
        #expect(kk_op_is(suspendRaw, functionToken(1)) == 1)
        #expect(kk_op_is(plainRaw, functionToken(0, suspend: true)) == 0)
        #expect(kk_op_is(plainRaw, functionToken(0)) == 1)
        #expect(kk_op_safe_cast(suspendRaw, functionToken(0, suspend: true)) == suspendRaw)
        #expect(kk_op_safe_cast(plainRaw, functionToken(0, suspend: true)) == runtimeNullSentinelInt)
    }

    @Test func taggedCallableReferencesMatchFunctionArity() {
        let function = kk_callable_ref_tag_kfunction(0x234500, 0, 0, 2, 0)
        #expect(kk_op_is(function, functionToken(2)) == 1)
        #expect(kk_op_is(function, functionToken(1)) == 0)
        let property = kk_callable_ref_tag_kproperty(0x345600, 0, 0, 0)
        #expect(kk_op_is(property, functionToken(0)) == 0)

        let suspendFunction = kk_callable_ref_tag_kfunction(0x456700, 0, 0, 1, 1)
        #expect(kk_op_is(suspendFunction, functionToken(1, suspend: true)) == 1)
        #expect(kk_op_is(suspendFunction, functionToken(1)) == 0)
        #expect(kk_op_is(suspendFunction, functionToken(2)) == 1)
    }

    @Test func callableReferenceMetadataSupportsNominalReflectionChecks() {
        func nominalToken(_ typeID: Int64) -> Int {
            Int((typeID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase)
        }
        let function = kk_callable_ref_tag_kfunction(0x234500, 0, 0, 1, 0)
        let copied = kk_function_create_1(0x456700, 0, nil)
        __kk_function_copy_description(function, copied)
        for value in [function, copied] {
            #expect(kk_op_is(value, nominalToken(kFunctionRuntimeTypeID)) == 1)
            #expect(kk_op_is(value, nominalToken(kCallableRuntimeTypeID)) == 1)
            #expect(kk_op_safe_cast(value, nominalToken(kFunctionRuntimeTypeID)) == value)
            #expect(kk_op_is(value, nominalToken(kPropertyRuntimeTypeID)) == 0)
        }
        let lambda = kk_function_value_tag_arity(0x567800, 1)
        #expect(kk_op_is(lambda, nominalToken(kFunctionRuntimeTypeID)) == 0)
        #expect(kk_op_is(lambda, nominalToken(kCallableRuntimeTypeID)) == 0)
        #expect(kk_op_is(runtimeNullSentinelInt, nominalToken(kCallableRuntimeTypeID)) == 0)
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
        let reflected = __kk_kfunction_create(0, 2, 0, 0, 0x567800, 0)
        #expect(kk_op_is(reflected, functionToken(2)) == 1)
        #expect(kk_op_is(reflected, functionToken(1)) == 0)
        #expect(kk_op_is(42, functionToken(1)) == 0)
    }

    @Test func boxedSuspendFunctionChecksRequireTheSuspendMarkerAndMatchingArity() {
        let regular = kk_function_create_0(0x123400, 0, nil)
        let suspended = kk_suspend_function_create(0x234500, 0, 0, 0x345600)

        #expect(kk_op_is(regular, functionToken(0)) == 1)
        #expect(kk_op_is(regular, functionToken(0, suspend: true)) == 0)
        #expect(kk_op_is(suspended, functionToken(0)) == 0)
        #expect(kk_op_is(suspended, functionToken(0, suspend: true)) == 1)
        #expect(kk_op_is(suspended, functionToken(1, suspend: true)) == 0)
    }

    @Test func suspendFunctionChecksAcceptNominalImplementations() {
        let customTypeID = runtimeStableNominalTypeID(fqName: "test.CustomSuspendFunction")
        let suspendFunction0ID = runtimeStableNominalTypeID(fqName: "kotlin.coroutines.SuspendFunction0")
        runtimeRegisterTypeEdge(childTypeID: customTypeID, parentTypeID: suspendFunction0ID)
        let value = kk_object_new(0, Int(customTypeID))

        #expect(kk_op_is(value, functionToken(0, suspend: true)) == 1)
        #expect(kk_op_is(value, functionToken(1, suspend: true)) == 0)
        #expect(kk_op_is(value, functionToken(0)) == 0)
    }
}
