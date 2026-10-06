@testable import Runtime
import Testing

private func callablePayload(_ receiver: Int) -> Int {
    kk_array_get_inbounds(receiver, 0)
}

private let callable0: KKClosureThunkEntryPoint = { receiver, thrown in
    thrown?.pointee = 0
    return kk_box_int(callablePayload(receiver))
}
private let callable1: KKClosureFunctionEntryPoint1 = { receiver, value, thrown in
    thrown?.pointee = 0
    return kk_box_int(callablePayload(receiver) + kk_unbox_int(value))
}
private let callable2: KKClosureFunctionEntryPoint2 = { receiver, a, b, thrown in
    thrown?.pointee = 0
    return kk_box_int(callablePayload(receiver) + kk_unbox_int(a) + kk_unbox_int(b))
}
private let callable3: KKClosureFunctionEntryPoint3 = { receiver, a, b, c, thrown in
    thrown?.pointee = 0
    return kk_box_int(callablePayload(receiver) + kk_unbox_int(a) + kk_unbox_int(b) + kk_unbox_int(c))
}
private let callable4: KKClosureFunctionEntryPoint4 = { receiver, a, b, c, d, thrown in
    thrown?.pointee = 0
    return kk_box_int(callablePayload(receiver) + kk_unbox_int(a) + kk_unbox_int(b) + kk_unbox_int(c) + kk_unbox_int(d))
}
private let callable5: KKClosureFunctionEntryPoint5 = { receiver, a, b, c, d, e, thrown in
    thrown?.pointee = 0
    return kk_box_int(callablePayload(receiver) + kk_unbox_int(a) + kk_unbox_int(b) + kk_unbox_int(c) + kk_unbox_int(d) + kk_unbox_int(e))
}
private let callable6: KKClosureFunctionEntryPoint6 = { receiver, a, b, c, d, e, f, thrown in
    thrown?.pointee = 0
    return kk_box_int(callablePayload(receiver) + kk_unbox_int(a) + kk_unbox_int(b) + kk_unbox_int(c) + kk_unbox_int(d) + kk_unbox_int(e) + kk_unbox_int(f))
}
private let callableIdentity: KKClosureFunctionEntryPoint1 = { _, value, thrown in
    thrown?.pointee = 0
    return value
}
private let callableThrow: KKClosureFunctionEntryPoint1 = { receiver, _, thrown in
    thrown?.pointee = callablePayload(receiver)
    return 0
}
private let rawIncrement: KKFunctionEntryPoint1 = { value, thrown in
    thrown?.pointee = 0
    return value + 1
}
private let capturedIncrement: KKClosureFunctionEntryPoint1 = { capture, value, thrown in
    thrown?.pointee = 0
    return capture + value
}

private func makeCallable(_ arity: Int, fnPtr: Int? = nil, payload: Int = 10) -> Int {
    let methods = [
        unsafeBitCast(callable0, to: Int.self), unsafeBitCast(callable1, to: Int.self),
        unsafeBitCast(callable2, to: Int.self), unsafeBitCast(callable3, to: Int.self),
        unsafeBitCast(callable4, to: Int.self), unsafeBitCast(callable5, to: Int.self),
        unsafeBitCast(callable6, to: Int.self),
    ]
    let object = kk_object_new(1, 0)
    var thrown = 0
    _ = kk_array_set(object, 0, payload, &thrown)
    let typeID = runtimeStableNominalTypeID(fqName: "kotlin.Function.Function\(arity)")
    _ = kk_object_register_itable_iface(object, Int(typeID), 3)
    _ = kk_object_register_itable_method(object, 3, 0, fnPtr ?? methods[arity])
    return object
}

private func invoke(_ arity: Int, _ function: Int, _ thrown: UnsafeMutablePointer<Int>) -> Int {
    switch arity {
    case 0: return kk_function_invoke_0(function, thrown)
    case 1: return kk_function_invoke(function, kk_box_int(1), thrown)
    case 2: return kk_function_invoke_2(function, kk_box_int(1), kk_box_int(2), thrown)
    case 3: return kk_function_invoke_3(function, kk_box_int(1), kk_box_int(2), kk_box_int(3), thrown)
    case 4: return kk_function_invoke_4(function, kk_box_int(1), kk_box_int(2), kk_box_int(3), kk_box_int(4), thrown)
    case 5: return kk_function_invoke_5(function, kk_box_int(1), kk_box_int(2), kk_box_int(3), kk_box_int(4), kk_box_int(5), thrown)
    default: return kk_function_invoke_6(function, kk_box_int(1), kk_box_int(2), kk_box_int(3), kk_box_int(4), kk_box_int(5), kk_box_int(6), thrown)
    }
}

private func wrap(_ arity: Int, _ function: Int, _ thrown: UnsafeMutablePointer<Int>) -> Int {
    switch arity {
    case 0: return kk_function_create_0(function, 0, thrown)
    case 1: return kk_function_create_1(function, 0, thrown)
    case 2: return kk_function_create_2(function, 0, thrown)
    case 3: return kk_function_create_3(function, 0, thrown)
    case 4: return kk_function_create_4(function, 0, thrown)
    case 5: return kk_function_create_5(function, 0, thrown)
    default: return kk_function_create_6(function, 0, thrown)
    }
}

@Suite(.runtimeIsolation(.all))
struct RuntimeFunctionObjectDispatchTests {
    @Test(arguments: 0...6)
    func dispatchesObjectAndKeepsBoxingIdempotent(arity: Int) {
        let object = makeCallable(arity)
        var thrown = 0
        #expect(kk_unbox_int(invoke(arity, object, &thrown)) == 10 + arity * (arity + 1) / 2)
        #expect(thrown == 0)
        #expect(wrap(arity, object, &thrown) == object)
        #expect(kk_function_value_closure_raw(object) == object)
        #expect(kk_function_value_fn_ptr(object) != object)
        #expect(thrown == 0)
    }

    @Test func retainsRawAndCapturedFunctionABIs() {
        var thrown = 0
        #expect(kk_function_invoke(unsafeBitCast(rawIncrement, to: Int.self), 3, &thrown) == 4)
        let function = kk_function_create_1(unsafeBitCast(capturedIncrement, to: Int.self), 10, &thrown)
        #expect(kk_function_invoke(function, 3, &thrown) == 13)
        #expect(kk_function_create_1(function, 0, &thrown) == function)
        #expect(thrown == 0)
    }

    @Test(arguments: 0...4)
    func dispatchesNativeCallbackPairs(arity: Int) {
        let object = makeCallable(arity)
        for pair in [(fnPtr: object, closureRaw: 0), resolveFunctionValuePair(fnPtr: object, closureRaw: 0)] {
            var thrown = 0
            let result: Int
            switch arity {
            case 0:
                result = runtimeInvokeClosureThunk(fnPtr: pair.fnPtr, closureRaw: pair.closureRaw, outThrown: &thrown)
            case 1:
                result = runtimeInvokeCollectionLambda1(fnPtr: pair.fnPtr, closureRaw: pair.closureRaw, value: kk_box_int(1), outThrown: &thrown)
            case 2:
                result = runtimeInvokeCollectionLambda2(fnPtr: pair.fnPtr, closureRaw: pair.closureRaw, lhs: kk_box_int(1), rhs: kk_box_int(2), outThrown: &thrown)
            case 3:
                result = runtimeInvokeCollectionLambda3(fnPtr: pair.fnPtr, closureRaw: pair.closureRaw, arg1: kk_box_int(1), arg2: kk_box_int(2), arg3: kk_box_int(3), outThrown: &thrown)
            default:
                result = runtimeInvokeCollectionLambda4(fnPtr: pair.fnPtr, closureRaw: pair.closureRaw, arg1: kk_box_int(1), arg2: kk_box_int(2), arg3: kk_box_int(3), arg4: kk_box_int(4), outThrown: &thrown)
            }
            #expect(kk_unbox_int(result) == 10 + arity * (arity + 1) / 2)
            #expect(thrown == 0)
        }
    }

    @Test func dispatchesResultCallbacks() {
        let supplier = makeCallable(0)
        let transform = makeCallable(1, fnPtr: unsafeBitCast(callableIdentity, to: Int.self))
        var thrown = 0
        let result = runtimeResultRunCatching(supplier, 0, &thrown)
        let value = runtimeResultValueOrNull(result)
        #expect(kk_unbox_int(value) == 10)
        let mapped = runtimeResultMap(result, transform, 0, &thrown)
        #expect(runtimeResultValueOrNull(mapped) == value)
        let pair = resolveFunctionValuePair(fnPtr: transform, closureRaw: 0)
        let mappedPair = runtimeResultMap(result, pair.fnPtr, pair.closureRaw, &thrown)
        #expect(runtimeResultValueOrNull(mappedPair) == value)
        #expect(thrown == 0)
        let invalid = runtimeResultRunCatching(kk_object_new(1, 0), 0, &thrown)
        #expect(runtimeResultIsFailure(invalid))
        #expect(thrown == 0)
    }

    @Test func preservesErasedArgumentsInNativeCallbacksAndSplitPairs() {
        let object = makeCallable(1, fnPtr: unsafeBitCast(callableIdentity, to: Int.self))
        let boxed = kk_box_int(123)
        var thrown = 0
        #expect(runtimeInvokeCollectionLambda1MaybeWrapped(fnPtr: object, closureRaw: 0, value: boxed, outThrown: &thrown) == boxed)
        #expect(runtimeInvokeCollectionLambda1(fnPtr: kk_function_value_fn_ptr(object), closureRaw: kk_function_value_closure_raw(object), value: boxed, outThrown: &thrown) == boxed)
        let pair = resolveFunctionValuePair(fnPtr: object, closureRaw: 0)
        #expect(runtimeInvokeCollectionLambda1PreservingBox(fnPtr: pair.fnPtr, closureRaw: pair.closureRaw, value: boxed, outThrown: &thrown) == boxed)
        #expect(thrown == 0)
    }

    @Test func propagatesExceptionsAndRejectsNoncallableObjectsAndWrongArity() {
        let error = runtimeAllocateThrowable(message: "getter failed")
        let object = makeCallable(1, fnPtr: unsafeBitCast(callableThrow, to: Int.self), payload: error)
        var thrown = 0
        #expect(kk_function_invoke(object, 0, &thrown) == 0)
        #expect(thrown == error)
        thrown = 0
        #expect(runtimeInvokeCollectionLambda1(fnPtr: object, closureRaw: 0, value: 0, outThrown: &thrown) == 0)
        #expect(thrown == error)
        for invalid in [kk_object_new(1, 0), registerRuntimeObject(RuntimeListBox(elements: [])), 0, runtimeNullSentinelInt] {
            thrown = 0
            #expect(kk_function_invoke(invalid, 0, &thrown) == 0)
            #expect(thrown != 0)
        }
        thrown = 0
        #expect(kk_function_invoke_0(object, &thrown) == 0)
        #expect(thrown != 0)
        thrown = 0
        #expect(kk_function_create_2(object, 0, &thrown) == 0)
        #expect(thrown != 0)
    }
}
