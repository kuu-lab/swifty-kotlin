@testable import Runtime
import Testing

private func callableVarargObservationBridge(
    _ environment: Int, _ arguments: Int, _ mask: Int, _ thrown: UnsafeMutablePointer<Int>?
) -> Int {
    thrown?.pointee = 0
    if let counter = runtimeArrayBox(from: environment) { counter[0] += 1 }
    return registerRuntimeObject(RuntimeListBox(elements: [
        kk_list_get(arguments, 0, nil), kk_box_int(mask),
    ]))
}

@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeCallableOmittedVarargTests {
    private func list(_ values: [Int]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: values))
    }

    private func callable(typeName: String, flags: Int, component: Int? = nil, environment: Int = 0) -> (Int, Int) {
        let typeID = runtimeStableNominalTypeID(fqName: typeName)
        let token = Int(RuntimeTypeTokenEncoding.nominalBase
            | ((typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift))
        let parameter = __kk_kparameter_create_typed(
            0, runtimeMakeStringRaw("values"), runtimeMakeStringRaw(typeName), flags, 2, token
        )
        if typeName == "kotlin.Array" {
            _ = __kk_kparameter_set_array_component(parameter, component ?? __kk_array_component_type(1, 0))
        }
        let raw = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 0, closureRaw: 0, arity: 1))
        let tagged = kk_callable_ref_tag_kfunction(raw, runtimeMakeStringRaw("observe"), runtimeMakeStringRaw("kotlin.Any"), 1, 0)
        let bridge: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = callableVarargObservationBridge
        _ = __kk_kcallable_register(tagged, unsafeBitCast(bridge, to: Int.self), environment,
                                    list([parameter]), list([]), 1, 0, 0, list([]))
        return (tagged, parameter)
    }

    @Test func omittedVarargHasEmptyCorrectlyTypedArrayAndNoDefaultMask() throws {
        for name in [
            "Array", "BooleanArray", "ByteArray", "CharArray", "DoubleArray",
            "FloatArray", "IntArray", "LongArray", "ShortArray", "UByteArray",
            "UShortArray", "UIntArray", "ULongArray",
        ] {
            let typeName = "kotlin.\(name)"
            let (raw, _) = callable(typeName: typeName, flags: 2)
            let map = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
            var thrown = 0
            let result = __kk_kcallable_call_by(raw, map, &thrown)
            #expect(thrown == 0)
            let observed = try #require(runtimeReflectionObject(from: result, as: RuntimeListBox.self))
            #expect(observed.elements.count == 2)
            let array = try #require(runtimeArrayBox(from: observed.elements[0]))
            #expect(array.elements.isEmpty)
            #expect(runtimeArrayTypeIDs(rawValue: observed.elements[0]) == [runtimeStableNominalTypeID(fqName: typeName)])
            #expect(kk_unbox_int(observed.elements[1]) == 0)
        }
    }

    @Test func optionalVarargUsesDefaultMaskAndExplicitArraysKeepIdentity() throws {
        let (optional, _) = callable(typeName: "kotlin.IntArray", flags: 3)
        let emptyMap = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0
        let optionalResult = __kk_kcallable_call_by(optional, emptyMap, &thrown)
        #expect(thrown == 0)
        let omitted = try #require(runtimeReflectionObject(from: optionalResult, as: RuntimeListBox.self))
        #expect(omitted.elements[0] == 0)
        #expect(kk_unbox_int(omitted.elements[1]) == 1)

        let (required, parameter) = callable(typeName: "kotlin.IntArray", flags: 2)
        let array = kk_array_new(0)
        runtimeRegisterArrayType(rawValue: array, typeID: runtimeStableNominalTypeID(fqName: "kotlin.IntArray"))
        let provided = registerRuntimeObject(RuntimeMapBox(keys: [parameter], values: [array]))
        let explicitResult = __kk_kcallable_call_by(required, provided, &thrown)
        #expect(thrown == 0)
        let explicit = try #require(runtimeReflectionObject(from: explicitResult, as: RuntimeListBox.self))
        #expect(explicit.elements[0] == array)
        #expect(kk_unbox_int(explicit.elements[1]) == 0)

        let wrong = kk_array_new(0)
        runtimeRegisterArrayType(rawValue: wrong, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))
        let wrongMap = registerRuntimeObject(RuntimeMapBox(keys: [parameter], values: [wrong]))
        #expect(__kk_kcallable_call_by(required, wrongMap, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
    }
    @Test func referenceEmptyComponentIsCheckedBeforeCallingAndIdentitySurvives() throws {
        let string = __kk_array_component_type(2, 0)
        let integer = __kk_array_component_type(3, 0)
        let counter = kk_array_new(1)
        let (raw, parameter) = callable(typeName: "kotlin.Array", flags: 2, component: string, environment: counter)
        let emptyMap = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0
        let omittedResult = __kk_kcallable_call_by(raw, emptyMap, &thrown)
        #expect(thrown == 0)
        let omitted = try #require(runtimeReflectionObject(from: omittedResult, as: RuntimeListBox.self))
        #expect(runtimeArrayBox(from: omitted.elements[0])?.componentType == string)
        let valid = kk_array_new(0)
        runtimeRegisterArrayType(rawValue: valid, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))
        _ = __kk_array_tag_component(valid, string)
        let validMap = registerRuntimeObject(RuntimeMapBox(keys: [parameter], values: [valid]))
        let result = __kk_kcallable_call_by(raw, validMap, &thrown)
        #expect(thrown == 0)
        #expect(runtimeReflectionObject(from: result, as: RuntimeListBox.self)?.elements[0] == valid)
        let counterBox = try #require(runtimeArrayBox(from: counter))
        let calls = counterBox[0]
        for component in [integer, 0] {
            let wrong = kk_array_new(0)
            runtimeRegisterArrayType(rawValue: wrong, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))
            if component != 0 { _ = __kk_array_tag_component(wrong, component) }
            let map = registerRuntimeObject(RuntimeMapBox(keys: [parameter], values: [wrong]))
            #expect(__kk_kcallable_call_by(raw, map, &thrown) == runtimeNullSentinelInt)
            #expect(thrown != 0)
            #expect(runtimeArrayBox(from: counter)?[0] == calls)
        }
    }

    @Test func componentCopyAndRetaggingKeepTheAllocationClassifier() throws {
        let string = __kk_array_component_type(2, 0)
        let any = __kk_array_component_type(1, 0)
        let raw = kk_array_new(0)
        _ = __kk_array_tag_component(raw, string)
        _ = __kk_array_tag_component(raw, any)
        #expect(runtimeArrayBox(from: raw)?.componentType == string)
        let copied = __kk_array_copyOf(raw)
        #expect(copied != raw && runtimeArrayBox(from: copied)?.componentType == string)
        let resized = __kk_array_new_same_component(raw, 2)
        #expect(runtimeArrayBox(from: resized)?.componentType == string)
        #expect(runtimeArrayBox(from: resized)?.elements == [runtimeNullSentinelInt, runtimeNullSentinelInt])
    }

    @Test func componentErasureIsNullableIndependentAndSupportsBoundsAndNestedArrays() {
        let nullableString = __kk_array_component_type(2 | Int(RuntimeTypeTokenEncoding.nullableBit), 0)
        let string = __kk_array_component_type(2, 0)
        let integer = __kk_array_component_type(3, 0)
        let any = __kk_array_component_type(1, 0)
        #expect(nullableString == string)
        func nominal(_ name: String) -> Int {
            Int(RuntimeTypeTokenEncoding.nominalBase | (runtimeStableNominalTypeID(fqName: name) << RuntimeTypeTokenEncoding.payloadShift))
        }
        let characterSequence = __kk_array_component_type(nominal("kotlin.CharSequence"), 0)
        #expect(runtimeArrayComponentIsAssignable(string, to: characterSequence))
        #expect(!runtimeArrayComponentIsAssignable(integer, to: characterSequence))
        #expect(runtimeArrayComponentIsAssignable(integer, to: any))
        let arraysOfString = __kk_array_component_type(nominal("kotlin.Array"), string)
        let arraysOfInt = __kk_array_component_type(nominal("kotlin.Array"), integer)
        let arraysOfAny = __kk_array_component_type(nominal("kotlin.Array"), any)
        #expect(runtimeArrayComponentIsAssignable(arraysOfString, to: arraysOfAny))
        #expect(!runtimeArrayComponentIsAssignable(arraysOfInt, to: arraysOfString))
        #expect(__kk_array_component_type(nominal("kotlin.Array"), 0) == 0, "An erased nested array cannot prove a component")
    }

    @Test(arguments: [false, true])
    func unknownDeclarationComponentRejectsOmittedAndExplicitArraysBeforeInvocation(explicit: Bool) throws {
        let counter = kk_array_new(1)
        let (raw, parameter) = callable(typeName: "kotlin.Array", flags: 2, component: 0, environment: counter)
        #expect(runtimeReflectionObject(from: parameter, as: RuntimeKParameterBox.self)?.arrayComponentType == 0)
        let map: Int
        if explicit {
            let array = kk_array_new(0)
            runtimeRegisterArrayType(rawValue: array, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))
            _ = __kk_array_tag_component(array, __kk_array_component_type(2, 0))
            map = registerRuntimeObject(RuntimeMapBox(keys: [parameter], values: [array]))
        } else {
            map = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        }
        let counterBox = try #require(runtimeArrayBox(from: counter))
        let before = counterBox[0]
        var thrown = 0
        #expect(__kk_kcallable_call_by(raw, map, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
        #expect(counterBox[0] == before, "invalid metadata rejects before the target callable executes")
    }

}
