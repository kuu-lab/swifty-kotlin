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

    @Test func suspendCastAcceptsLoweredFunctionShape() {
        // KUU-3801: `x as suspend (P1..Pn) -> R` is a JVM checkcast of the
        // lowered `Function{n+1}` shape — a plain
        // `(P1..Pn, Continuation<R>) -> Any?` value passes, while `is`/`as?`
        // keep requiring the SuspendFunction marker.
        let erasedRaw = 0x123700      // (Continuation<Unit>) -> Any?, Function1
        let suspendRaw = 0x123800     // suspend () -> Unit
        let wrongArityRaw = 0x123900  // () -> Unit, Function0
        _ = kk_function_value_tag_arity(erasedRaw, 1)
        _ = kk_function_value_tag_arity(suspendRaw, 0x100)
        _ = kk_function_value_tag_arity(wrongArityRaw, 0)

        var thrown = 0
        #expect(kk_op_cast(erasedRaw, functionToken(0, suspend: true), &thrown) == erasedRaw)
        #expect(thrown == 0)
        #expect(kk_op_cast(suspendRaw, functionToken(0, suspend: true), &thrown) == suspendRaw)
        #expect(thrown == 0)
        _ = kk_op_cast(wrongArityRaw, functionToken(0, suspend: true), &thrown)
        #expect(thrown != 0)
        thrown = 0

        // The boxed Function1 path answers the same lowered-shape check.
        let boxed = kk_function_create_1(0x456700, 0, nil)
        #expect(kk_op_cast(boxed, functionToken(0, suspend: true), &thrown) == boxed)
        #expect(thrown == 0)

        // A true suspend lambda still passes, at its declared arity only.
        let suspended = kk_suspend_function_create(0x234500, 0, 0, 0x345600)
        #expect(kk_op_cast(suspended, functionToken(0, suspend: true), &thrown) == suspended)
        #expect(thrown == 0)
        _ = kk_op_cast(suspended, functionToken(1, suspend: true), &thrown)
        #expect(thrown != 0)
        thrown = 0

        // `is`/`as?` keep the marker check: the erased Function1 shape is
        // not a SuspendFunction0.
        #expect(kk_op_is(erasedRaw, functionToken(0, suspend: true)) == 0)
        #expect(kk_op_safe_cast(erasedRaw, functionToken(0, suspend: true)) == runtimeNullSentinelInt)

        // Arity scales: (P, Continuation<R>) -> Any? as suspend (P) -> R.
        let erasedUnaryRaw = 0x124000  // Function2
        _ = kk_function_value_tag_arity(erasedUnaryRaw, 2)
        #expect(kk_op_cast(erasedUnaryRaw, functionToken(1, suspend: true), &thrown) == erasedUnaryRaw)
        #expect(thrown == 0)
        _ = kk_op_cast(erasedUnaryRaw, functionToken(0, suspend: true), &thrown)
        #expect(thrown != 0)
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

    @Test func samCallableAdaptersRespectNominalFunctionSupertypes() {
        let actionID = runtimeStableNominalTypeID(fqName: "test.Action")
        let actionWrapperID = runtimeStableNominalTypeID(fqName: "test.ActionWrapper")
        let functionActionID = runtimeStableNominalTypeID(fqName: "test.FunctionAction")
        let functionWrapperID = runtimeStableNominalTypeID(fqName: "test.FunctionActionWrapper")
        let suspendedID = runtimeStableNominalTypeID(fqName: "test.SuspendedAction")
        let suspendedWrapperID = runtimeStableNominalTypeID(fqName: "test.SuspendedActionWrapper")
        let suspendFunctionID = runtimeStableNominalTypeID(fqName: "test.SuspendFunctionAction")
        let suspendWrapperID = runtimeStableNominalTypeID(fqName: "test.SuspendFunctionActionWrapper")
        let function0ID = runtimeStableNominalTypeID(fqName: "kotlin.Function.Function0")
        let suspendFunction0ID = runtimeStableNominalTypeID(fqName: "kotlin.coroutines.SuspendFunction0")

        runtimeRegisterTypeEdge(childTypeID: actionWrapperID, parentTypeID: actionID)
        runtimeRegisterTypeEdge(childTypeID: functionWrapperID, parentTypeID: functionActionID)
        runtimeRegisterTypeEdge(childTypeID: functionActionID, parentTypeID: function0ID)
        runtimeRegisterTypeEdge(childTypeID: suspendedWrapperID, parentTypeID: suspendedID)
        runtimeRegisterTypeEdge(childTypeID: suspendWrapperID, parentTypeID: suspendFunctionID)
        runtimeRegisterTypeEdge(childTypeID: suspendFunctionID, parentTypeID: suspendFunction0ID)

        let action = kk_object_new(2, Int(actionWrapperID))
        let functionAction = kk_object_new(2, Int(functionWrapperID))
        let suspended = kk_object_new(2, Int(suspendedWrapperID))
        let suspendFunctionAction = kk_object_new(2, Int(suspendWrapperID))
        __kk_sam_adapter_set_identity(action, Int(actionID), 0x123400, runtimeNullSentinelInt, 0, 0)
        __kk_sam_adapter_set_identity(functionAction, Int(functionActionID), 0x123400, runtimeNullSentinelInt, 0, 0)
        __kk_sam_adapter_set_identity(suspended, Int(suspendedID), 0x123400, runtimeNullSentinelInt, 0, 1)
        __kk_sam_adapter_set_identity(suspendFunctionAction, Int(suspendFunctionID), 0x123400, runtimeNullSentinelInt, 0, 1)
        // A stale function tag must not override the SAM's nominal identity.
        _ = kk_function_value_tag_arity(action, 0)

        #expect(kk_op_is(action, functionToken(0)) == 0)
        #expect(kk_op_is(functionAction, functionToken(0)) == 1)
        #expect(kk_op_is(functionAction, functionToken(1)) == 0)
        #expect(kk_op_is(suspended, functionToken(1)) == 0)
        #expect(kk_op_is(suspendFunctionAction, functionToken(1)) == 1)
        #expect(kk_op_is(suspendFunctionAction, functionToken(0, suspend: true)) == 1)

        let function = kk_function_create_0(0x123400, 0, nil)
        __kk_callable_adapter_set_identity(function, 0, 0x123400, runtimeNullSentinelInt, 0, 0, 0)
        #expect(kk_op_is(function, functionToken(0)) == 1)
        #expect(kk_op_is(function, functionToken(1)) == 0)
    }
}
