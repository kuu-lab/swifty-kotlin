@testable import Runtime
import Testing

private func callableSumBridge(_ environment: Int, _ arguments: Int, _ mask: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    let first = mask & 1 == 0 ? kk_unbox_int(kk_list_get(arguments, 0, nil)) : 8
    let second = mask & 2 == 0 ? kk_unbox_int(kk_list_get(arguments, 1, nil)) : 2
    return kk_box_int(first + second + environment)
}

private func callableThrowingBridge(_ environment: Int, _ arguments: Int, _ mask: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "boom")
    return runtimeNullSentinelInt
}

@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeCallableInvocationTests {
    private func list(_ elements: [Int]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: elements))
    }

    private func function() -> (Int, [Int]) {
        let raw = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 0, closureRaw: 0, arity: 2))
        let tagged = kk_callable_ref_tag_kfunction(raw, runtimeMakeStringRaw("sum"), runtimeMakeStringRaw("kotlin.Int"), 2, 0)
        let parameters = (0..<2).map {
            __kk_kparameter_create($0, runtimeMakeStringRaw($0 == 0 ? "a" : "b"), runtimeMakeStringRaw("kotlin.Int"), 1, 2)
        }
        let bridge: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = callableSumBridge
        _ = __kk_kcallable_register(tagged, unsafeBitCast(bridge, to: Int.self), 0, list(parameters), list([]), 1, 0, 0, list([]))
        return (tagged, parameters)
    }

    @Test func callAndCallByUseRegisteredBridgeAndDefaultMask() {
        let (raw, parameters) = function()
        var thrown = 0
        #expect(kk_unbox_int(__kk_kcallable_call(raw, list([kk_box_int(3), kk_box_int(4)]), &thrown)) == 7)
        #expect(thrown == 0)
        let map = registerRuntimeObject(RuntimeMapBox(keys: [parameters[1]], values: [kk_box_int(11)]))
        #expect(kk_unbox_int(__kk_kcallable_call_by(raw, map, &thrown)) == 19)
        #expect(thrown == 0)
        let emptyMap = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        #expect(kk_unbox_int(__kk_kcallable_call_by(raw, emptyMap, &thrown)) == 10)
        #expect(thrown == 0)
        #expect(__kk_kcallable_get_metadata(raw, 0) != 0)
        #expect(__kk_kcallable_get_metadata(raw, 3) == 1)
        #expect(__kk_kcallable_get_metadata(raw, 4) == 0)
        #expect(__kk_kcallable_get_metadata(raw, 5) == 0)
        #expect(__kk_kcallable_get_metadata(raw, 6) == 0)
    }

    @Test func boxedReferencePreservesCompleteReflectionMetadataWithoutDescription() {
        let (source, parameters) = function()
        let wrapper = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 1, closureRaw: 0, arity: 2))
        __kk_function_copy_description(source, wrapper)
        #expect(__kk_kcallable_get_name(wrapper) == __kk_kcallable_get_name(source))
        #expect(runtimeStorage.withDelegateLock { state in
            state.callableRefMetadataByValue[wrapper]?.returnTypeRaw == state.callableRefMetadataByValue[source]?.returnTypeRaw
        })
        #expect(__kk_kcallable_get_metadata(wrapper, 0) == __kk_kcallable_get_metadata(source, 0))
        var thrown = 0
        #expect(kk_unbox_int(__kk_kcallable_call(wrapper, list([kk_box_int(3), kk_box_int(4)]), &thrown)) == 7)
        #expect(thrown == 0)
        let map = registerRuntimeObject(RuntimeMapBox(keys: [parameters[1]], values: [kk_box_int(11)]))
        #expect(kk_unbox_int(__kk_kcallable_call_by(wrapper, map, &thrown)) == 19)
        #expect(thrown == 0)
    }

    @Test func callableAnnotationsPreserveRecordsThroughBoxing() throws {
        let (source, _) = function()
        _ = __kk_kcallable_register_single_annotation(
            source, runtimeMakeStringRaw("sample.Marker"), runtimeMakeStringRaw("value=7"), 1
        )
        _ = __kk_kcallable_register_single_annotation(
            source, runtimeMakeStringRaw("kotlin.Metadata"), runtimeMakeStringRaw(""), 0
        )
        let wrapper = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 1, closureRaw: 0, arity: 2))
        __kk_function_copy_description(source, wrapper)
        for raw in [source, wrapper] {
            let annotations = try #require(runtimeReflectionObject(
                from: __kk_kcallable_get_metadata(raw, 12), as: RuntimeListBox.self
            ))
            #expect(annotations.elements.count == 1)
            let annotationRaw = try #require(annotations.elements.first)
            let annotation = try #require(runtimeReflectionObject(from: annotationRaw, as: RuntimeAnnotationBox.self))
            #expect(annotation.annotationFQName == "sample.Marker")
            #expect(annotation.arguments == ["value=7"])
        }
        let (plain, _) = function()
        let empty = try #require(runtimeReflectionObject(
            from: __kk_kcallable_get_metadata(plain, 12), as: RuntimeListBox.self
        ))
        #expect(empty.elements.isEmpty)
    }

    @Test func invalidArityAndMissingRequiredArgumentsThrow() {
        let (raw, _) = function()
        var thrown = 0
        #expect(__kk_kcallable_call(raw, list([]), &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
        let required = __kk_kparameter_create(0, runtimeMakeStringRaw("a"), runtimeMakeStringRaw("kotlin.Int"), 0, 2)
        let optional = __kk_kparameter_create(1, runtimeMakeStringRaw("b"), runtimeMakeStringRaw("kotlin.Int"), 1, 2)
        let bridge: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = callableSumBridge
        _ = __kk_kcallable_register(raw, unsafeBitCast(bridge, to: Int.self), 0, list([required, optional]), list([]), 1, 0, 0, list([]))
        let emptyMap = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        #expect(__kk_kcallable_call_by(raw, emptyMap, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
    }

    @Test func bridgeExceptionsPropagateWithoutChangingUserObjects() {
        let (raw, _) = function()
        let bridge: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = callableThrowingBridge
        _ = __kk_kcallable_register(raw, unsafeBitCast(bridge, to: Int.self), 0, list([]), list([]), 1, 0, 0, list([]))
        var thrown = 0
        #expect(__kk_kcallable_call(raw, list([kk_box_int(1), kk_box_int(2)]), &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
        #expect(__kk_kcallable_is_runtime(raw) == 1)
        #expect(__kk_kcallable_is_runtime(list([])) == 0)
    }

    @Test func typedParametersRejectWrongTypesAndNull() {
        let (raw, _) = function()
        let required = __kk_kparameter_create_typed(0, runtimeMakeStringRaw("a"), runtimeMakeStringRaw("kotlin.Int"), 0, 2, 3)
        let optional = __kk_kparameter_create_typed(1, runtimeMakeStringRaw("b"), runtimeMakeStringRaw("kotlin.Int"), 1, 2, 3)
        let bridge: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = callableSumBridge
        _ = __kk_kcallable_register(raw, unsafeBitCast(bridge, to: Int.self), 0, list([required, optional]), list([]), 1, 0, 0, list([]))
        var thrown = 0
        #expect(__kk_kcallable_call(raw, list([runtimeMakeStringRaw("wrong"), kk_box_int(1)]), &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
        #expect(__kk_kcallable_call(raw, list([runtimeNullSentinelInt, kk_box_int(1)]), &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
        let map = registerRuntimeObject(RuntimeMapBox(keys: [required], values: [runtimeMakeStringRaw("wrong")]))
        #expect(__kk_kcallable_call_by(raw, map, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
    }

    @Test func callByMatchesParametersFromEquivalentReferencesOnly() {
        let (raw, _) = function()
        let parameter = __kk_kparameter_create_typed(0, runtimeMakeStringRaw("a"), runtimeMakeStringRaw("kotlin.Int"), 0, 2, 3, 123)
        let optional = __kk_kparameter_create_typed(1, runtimeMakeStringRaw("b"), runtimeMakeStringRaw("kotlin.Int"), 1, 2, 3, 123)
        let equivalent = __kk_kparameter_create_typed(0, runtimeMakeStringRaw("a"), runtimeMakeStringRaw("kotlin.Int"), 0, 2, 3, 123)
        let unrelated = __kk_kparameter_create_typed(0, runtimeMakeStringRaw("a"), runtimeMakeStringRaw("kotlin.Int"), 0, 2, 3, 124)
        let bridge: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = callableSumBridge
        _ = __kk_kcallable_register(raw, unsafeBitCast(bridge, to: Int.self), 0, list([parameter, optional]), list([]), 1, 0, 0, list([]))
        var thrown = 0
        let matching = registerRuntimeObject(RuntimeMapBox(keys: [equivalent], values: [kk_box_int(5)]))
        #expect(kk_unbox_int(__kk_kcallable_call_by(raw, matching, &thrown)) == 7)
        #expect(thrown == 0)
        let foreign = registerRuntimeObject(RuntimeMapBox(keys: [unrelated], values: [kk_box_int(5)]))
        #expect(__kk_kcallable_call_by(raw, foreign, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
    }
}
