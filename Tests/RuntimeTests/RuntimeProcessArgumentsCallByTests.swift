@testable import Runtime
import RuntimeABI
import Testing

private func processArgumentsWholeArrayBridge(
    _ environment: Int, _ arguments: Int, _ mask: Int, _ thrown: UnsafeMutablePointer<Int>?
) -> Int {
    thrown?.pointee = 0
    if let observed = runtimeArrayBox(from: environment) {
        observed[0] += 1
        observed[1] = mask
    }
    return kk_list_get(arguments, 0, nil)
}

@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeProcessArgumentsCallByTests {
    private func list(_ values: [Int]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: values))
    }

    private func arguments(_ values: [String]) -> Int {
        let strings = ["program"] + values
        let buffers = strings.map { text -> UnsafeMutablePointer<UInt8> in
            let bytes = Array(text.utf8) + [0]
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
            bytes.withUnsafeBufferPointer { buffer.initialize(from: $0.baseAddress!, count: $0.count) }
            return buffer
        }
        let argv = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: buffers.count + 1)
        argv.initialize(repeating: nil, count: buffers.count + 1)
        for (index, buffer) in buffers.enumerated() { argv[index] = UnsafePointer(buffer) }
        defer {
            argv.deinitialize(count: buffers.count + 1)
            argv.deallocate()
            for buffer in buffers { buffer.deallocate() }
        }
        return __kk_process_args_from_argv(Int32(strings.count), UnsafeRawPointer(argv))
    }

    @Test(arguments: [false, true])
    func cliArgumentsAreAcceptedAsTheWholeStringVarargArray(nonempty: Bool) throws {
        let expected = nonempty ? ["", "日本語😀"] : []
        // The foreign argv buffers have been freed before callBy uses the array.
        let array = arguments(expected)
        let box = try #require(runtimeArrayBox(from: array))
        let stringComponent = __kk_array_component_type(2, 0)
        #expect(stringComponent != 0)
        #expect(box.componentType == stringComponent)
        #expect(box.elements.compactMap(runtimeStringFromRaw) == expected)
        let arrayTypeID = runtimeStableNominalTypeID(fqName: "kotlin.Array")
        #expect(runtimeArrayHasType(rawValue: array, typeID: arrayTypeID))
        let token = Int(RuntimeTypeTokenEncoding.nominalBase
            | ((arrayTypeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift))
        let parameter = __kk_kparameter_create_typed(
            0, runtimeMakeStringRaw("values"), runtimeMakeStringRaw("kotlin.Array"), 2, 2, token
        )
        _ = __kk_kparameter_set_array_component(parameter, stringComponent)
        let observed = kk_array_new(2)
        let function = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 0, closureRaw: 0, arity: 1))
        let callable = kk_callable_ref_tag_kfunction(function, runtimeMakeStringRaw("words"),
            runtimeMakeStringRaw("kotlin.Array"), 1, 0)
        let bridge: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = processArgumentsWholeArrayBridge
        _ = __kk_kcallable_register(callable, unsafeBitCast(bridge, to: Int.self), observed,
            list([parameter]), list([]), 1, 0, 0, list([]))
        let map = registerRuntimeObject(RuntimeMapBox(keys: [parameter], values: [array]))
        var thrown = 0
        let returned = __kk_kcallable_call_by(callable, map, &thrown)
        #expect(thrown == 0)
        #expect(returned == array, "Reflection passes the entire argv array without copying")
        let observation = try #require(runtimeArrayBox(from: observed))
        #expect(observation[0] == 1)
        #expect(observation[1] == 0, "An explicit array does not set a default mask")
        #expect(box.elements.count == expected.count)
        _ = __kk_array_tag_component(array, __kk_array_component_type(1, 0))
        #expect(box.componentType == stringComponent, "The allocation component cannot be widened")
    }
}
