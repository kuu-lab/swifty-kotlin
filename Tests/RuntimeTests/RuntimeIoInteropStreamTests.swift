import Foundation
@testable import Runtime
import Testing

private let ioReadThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    guard let state = runtimeArrayBox(from: raw) else { return -1 }
    state[0] += 1
    thrown?.pointee = state[1]
    return 255
}
private let ioRangeThunk: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, bytes, offset, count, thrown in
    guard let state = runtimeArrayBox(from: raw) else { return -1 }
    state[0] += 1
    state[2] = bytes
    state[3] = offset
    state[4] = count
    thrown?.pointee = state[1]
    if state[1] == 0, let data = runtimeArrayBox(from: bytes), count > 0, offset >= 0, offset < data.count {
        data[offset] = -1
    }
    return 1
}
private let ioFiniteRangeThunk: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, bytes, offset, count, thrown in
    thrown?.pointee = 0
    guard let state = runtimeArrayBox(from: raw), let destination = runtimeArrayBox(from: bytes) else { return -1 }
    let remaining = state.count - 1 - state[0]
    if remaining == 0 { return -1 }
    let copied = min(remaining, count)
    for index in 0..<copied { destination[offset + index] = state[1 + state[0] + index] }
    state[0] += copied
    return copied
}
private let ioByteArrayWholeArrayBridge: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { environment, arguments, mask, thrown in
    thrown?.pointee = 0
    if let state = runtimeArrayBox(from: environment) { state[0] += 1; state[1] = mask }
    return kk_list_get(arguments, 0, nil)
}
private let ioAvailableThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    guard let state = runtimeArrayBox(from: raw) else { return 0 }
    thrown?.pointee = state[1]
    return 7
}
private let ioCloseThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    guard let state = runtimeArrayBox(from: raw) else { return 0 }
    state[5] += 1
    thrown?.pointee = state[1]
    return 0
}
private let ioDescriptionThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    let state = runtimeArrayBox(from: raw)
    thrown?.pointee = state?[1] ?? 0
    return runtimeMakeStringRaw("callback-\(state?[0] ?? 0)")
}
private let ioNoopThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in 0 }

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeIoInteropStreamTests {
    private func array(_ values: [Int]) -> Int { runtimeMakeArrayRaw(values) }
    private func values(_ raw: Int) throws -> [Int] {
        let box = try #require(runtimeArrayBox(from: raw))
        return (0..<box.count).map { box[$0] }
    }
    private func encoded(_ value: String, tag: Int) -> Int {
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = runtimeRegisterFlatString(value, outLength: &length, outByteCount: &byteCount, outHash: &hash)
        return __kk_string_toByteArray_charset_flat(data.map { UnsafePointer($0) }, length, byteCount, hash, tag)
    }
    private func input(_ state: Int) -> Int {
        __kk_kotlin_source_input_stream(unsafeBitCast(ioReadThunk, to: Int.self), state,
            unsafeBitCast(ioRangeThunk, to: Int.self), state,
            unsafeBitCast(ioAvailableThunk, to: Int.self), state,
            unsafeBitCast(ioCloseThunk, to: Int.self), state,
            unsafeBitCast(ioDescriptionThunk, to: Int.self), state)
    }
    private func output(_ state: Int) -> Int {
        __kk_kotlin_sink_output_stream_range(unsafeBitCast(ioRangeThunk, to: Int.self), state,
            unsafeBitCast(ioNoopThunk, to: Int.self), state,
            unsafeBitCast(ioCloseThunk, to: Int.self), state,
            unsafeBitCast(ioDescriptionThunk, to: Int.self), state)
    }

    @Test func sourceCallbacksRemainLazyAndPreserveRangesAndThrowableIdentity() throws {
        let stateRaw = array([0, 0, 0, 0, 0, 0])
        let state = try #require(runtimeArrayBox(from: stateRaw))
        let stream = input(stateRaw)
        #expect(state[0] == 0)
        var thrown = 0
        #expect(__kk_input_stream_read(stream, &thrown) == 255 && thrown == 0)
        let destination = array([11, 22, 33])
        #expect(__kk_input_stream_read_range(stream, destination, 1, 1, &thrown) == 1)
        #expect(state[2] == destination && state[3] == 1 && state[4] == 1)
        #expect(try values(destination) == [11, -1, 33])
        #expect(__kk_input_stream_available_throwing(stream, &thrown) == 7)
        let failure = runtimeAllocateIOException(message: "original source failure")
        state[1] = failure
        _ = __kk_input_stream_read_range(stream, destination, -1, 1, &thrown)
        #expect(thrown == failure, "The Kotlin closed check must run before native range validation")
        _ = __kk_input_stream_available_throwing(stream, &thrown)
        #expect(thrown == failure)
        let closeAddress = kk_itable_lookup_dynamic(stream, Int(runtimeStableNominalTypeID(fqName: "kotlin.AutoCloseable")), 0)
        try #require(closeAddress != 0)
        let close = unsafeBitCast(closeAddress, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        _ = close(stream, &thrown)
        #expect(state[5] == 1 && thrown == failure)
        #expect(runtimeKotlinInputStream(from: stream)?.childRefs.contains(stateRaw) == true)
    }

    @Test func sinkCallbacksSeeTheOriginalArrayAndErrorsBeforeBounds() throws {
        let stateRaw = array([0, 0, 0, 0, 0, 0])
        let state = try #require(runtimeArrayBox(from: stateRaw))
        let stream = output(stateRaw)
        let original = array([1, 2, 3])
        var thrown = 0
        _ = __kk_output_stream_write_range(stream, original, 1, 1, &thrown)
        #expect(thrown == 0 && state[2] == original && state[3] == 1 && state[4] == 1)
        let failure = runtimeAllocateIOException(message: "original sink failure")
        state[1] = failure
        _ = __kk_output_stream_write_range(stream, original, -1, 1, &thrown)
        #expect(thrown == failure && state[3] == -1)
        _ = __kk_output_stream_close_throwing(stream, &thrown)
        #expect(thrown == failure && state[5] == 1)
        let object = try #require(UnsafeMutableRawPointer(bitPattern: stream))
        #expect(tryCast(object, to: RuntimeOutputStreamBox.self)?.childRefs.contains(stateRaw) == true)
    }

    @Test func memoryInputSharesItsArrayAndOutputSnapshotsRemainIsolated() throws {
        let original = array([1, 2, 3])
        let source = try #require(runtimeArrayBox(from: original))
        var thrown = 0
        let stream = __kk_bytearrayinputstream_new(original, &thrown)
        #expect(thrown == 0)
        source[0] = 9
        #expect(__kk_input_stream_read(stream, &thrown) == 9)
        let object = try #require(UnsafeMutableRawPointer(bitPattern: stream))
        let memory = try #require(tryCast(object, to: RuntimeInputStreamBox.self))
        #expect(memory.markSupported())
        memory.mark(readLimit: 0)
        #expect(memory.readByte() == 2 && memory.reset())
        source[1] = 8
        #expect(memory.readByte() == 8)
        memory.close()
        #expect(memory.readByte() == 3 && memory.reset() && memory.readByte() == 8)
        #expect(memory.childRefs == [original])
        let sink = __kk_bytearray_output_stream_new(0, &thrown)
        _ = __kk_output_stream_write_range(sink, original, 1, 2, &thrown)
        let snapshot = __kk_bytearray_output_stream_to_byte_array(sink)
        let copy = try #require(runtimeArrayBox(from: snapshot))
        copy[0] = 99
        #expect(try values(__kk_bytearray_output_stream_to_byte_array(sink)) == [8, 3])
        _ = __kk_output_stream_close_throwing(sink, &thrown)
        _ = __kk_output_stream_write_byte(sink, 255, &thrown)
        #expect(try values(__kk_bytearray_output_stream_to_byte_array(sink)) == [8, 3, -1])
        _ = __kk_output_stream_write_range(sink, original, -1, 1, &thrown)
        #expect(thrown != 0 && __kk_bytearray_output_stream_size(sink) == 3)
        thrown = 0
        #expect(__kk_bytearray_output_stream_new(-1, &thrown) == 0 && thrown != 0)
    }

    @Test func explicitCharsetsFollowObservedJDKEmptySurrogateAndMalformedGrouping() throws {
        // Expected bytes/code units are pinned to the distinct JVM reference
        // fixtures, not derived by calling the implementation under test.
        for tag in [0, 1, 2, 3, 4, 5] {
            #expect(try values(encoded("", tag: tag)) == [])
        }
        let isolated = runtimeKotlinStringFromUTF16CodeUnits([0xd800])
        #expect(try values(encoded(isolated, tag: 0)) == [63])
        #expect(try values(encoded(isolated, tag: 4)) == [-1, -3])
        let pair = runtimeKotlinStringFromUTF16CodeUnits([0xd800, 0xdc00])
        #expect(try values(encoded(pair, tag: 1)) == [63])
        let controls: [([Int], [UInt16])] = [
            ([-64, -81], [65533, 65533]), ([-19, -96, -128], [65533]),
            ([-30, -126], [65533]), ([-30, 65], [65533, 65]),
        ]
        for (bytes, expected) in controls {
            let decoded = __kk_bytearray_decodeToString_charset(array(bytes), 0)
            #expect(runtimeStringUTF16CodeUnits(decoded) == expected)
        }
    }

    @Test func charsetWriterWrapsMemoryAndCallbackStreamsAndKeepsCloseFailureIdentity() throws {
        var thrown = 0
        let sink = __kk_bytearray_output_stream_new_default()
        let writer = __kk_output_stream_bufferedWriter(sink, 1)
        _ = __kk_buffered_writer_write(writer, runtimeMakeStringRaw("é"), &thrown)
        #expect(thrown == 0 && __kk_bytearray_output_stream_size(sink) == 0)
        _ = __kk_buffered_writer_flush(writer, &thrown)
        #expect(try values(__kk_bytearray_output_stream_to_byte_array(sink)) == [-23])
        _ = __kk_buffered_writer_close_throwing(writer, &thrown)
        _ = __kk_buffered_writer_write(writer, runtimeMakeStringRaw("x"), &thrown)
        #expect(thrown != 0 && __kk_bytearray_output_stream_size(sink) == 1)
        let stateRaw = array([0, 0, 0, 0, 0, 0])
        let state = try #require(runtimeArrayBox(from: stateRaw))
        let callbackWriter = __kk_output_stream_bufferedWriter(output(stateRaw), 4)
        let failure = runtimeAllocateIOException(message: "writer close callback failure")
        state[1] = failure
        _ = __kk_buffered_writer_close_throwing(callbackWriter, &thrown)
        #expect(thrown == failure && state[5] == 1)
    }
    @Test func lazyDescriptionsKeepDynamicStateAndTypedInterpolationFailureIdentity() throws {
        let stateRaw = array([0, 0, 0, 0, 0, 0])
        let state = try #require(runtimeArrayBox(from: stateRaw))
        let source = input(stateRaw)
        let sink = output(stateRaw)
        var thrown = 0
        #expect(runtimeStringFromRaw(__kk_io_stream_to_string(source, &thrown)) == "callback-0" && thrown == 0)
        state[0] = 7
        #expect(runtimeStringFromRaw(__kk_io_stream_to_string(source, &thrown)) == "callback-7")
        #expect(runtimeStringFromRaw(__kk_io_stream_to_string(sink, &thrown)) == "callback-7")
        #expect(extractString(from: kk_any_to_string(source, 1)) == "callback-7")
        let failure = runtimeAllocateIOException(message: "original description")
        state[1] = failure
        _ = __kk_io_stream_to_string(source, &thrown)
        #expect(thrown == failure)
        _ = __kk_io_stream_to_string(sink, &thrown)
        #expect(thrown == failure)
        _ = __kk_any_to_string_throwing(source, 1, &thrown)
        #expect(thrown == failure, "Object interpolation must preserve the original exception")
    }

    @Test func sequenceInputStreamAcceptsCallbackHandlesAndClosesBoth() throws {
        let stateRaw = array([0, 0, 0, 0, 0, 0])
        let state = try #require(runtimeArrayBox(from: stateRaw))
        let callback = input(stateRaw)
        var thrown = 0
        let secondStateRaw = array([0, 0, 0, 0, 0, 0])
        let secondState = try #require(runtimeArrayBox(from: secondStateRaw))
        let second = input(secondStateRaw)
        let sequence = __kk_sequence_input_stream_new(callback, second)
        #expect(state[0] == 0, "Construction must not read either stream")
        #expect(__kk_sequence_input_stream_read(sequence, &thrown) == 255 && state[0] == 1)
        #expect(__kk_sequence_input_stream_available_throwing(sequence, &thrown) == 7)
        let failure = runtimeAllocateIOException(message: "sequence original read failure")
        state[1] = failure
        _ = __kk_input_stream_read(sequence, &thrown)
        #expect(thrown == failure)
        let zero = array([])
        _ = __kk_input_stream_read_range(sequence, zero, -1, 0, &thrown)
        #expect(thrown != 0 && thrown != failure, "Sequence validates range before closed Source callback")
        _ = __kk_sequence_input_stream_close_throwing(sequence, &thrown)
        #expect(thrown == failure && state[5] == 1)
        #expect(secondState[5] == 1, "The second Source must close even when the first close throws")
        state[1] = 0
        #expect(__kk_sequence_input_stream_read(sequence, &thrown) == -1)
        #expect(__kk_input_stream_read_range(sequence, zero, -1, 0, &thrown) == -1 && thrown == 0)
        let empty = __kk_sequence_input_stream_new(__kk_bytearrayinputstream_new(zero, &thrown), __kk_bytearrayinputstream_new(zero, &thrown))
        #expect(__kk_input_stream_read_range(empty, zero, 0, 0, &thrown) == 0 && thrown == 0)
        let first = __kk_bytearrayinputstream_new(array([1, 2]), &thrown)
        let tailStream = __kk_bytearrayinputstream_new(array([3]), &thrown)
        let chain = __kk_sequence_input_stream_new(first, tailStream)
        let destination = array([9, 9, 9])
        #expect(__kk_input_stream_read_range(chain, destination, 1, 2, &thrown) == 2)
        #expect(try values(destination) == [9, 1, 2])
        let nested = __kk_sequence_input_stream_new(chain, __kk_bytearrayinputstream_new(array([4]), &thrown))
        let remaining = __kk_input_stream_readAllBytes(nested, &thrown)
        #expect(try values(remaining) == [3, 4])
        #expect(thrown == 0)
        let copyChain = __kk_sequence_input_stream_new(
            __kk_bytearrayinputstream_new(array([1, 2]), &thrown),
            __kk_bytearrayinputstream_new(array([3]), &thrown))
        #expect(kk_unbox_bool(__kk_input_stream_mark_supported(copyChain)) == 0)
        let copied = __kk_bytearray_output_stream_new_default()
        #expect(kk_unbox_long(__kk_input_stream_copyTo(copyChain, copied, kk_box_int(1), &thrown)) == 3)
        let copiedBytes = try values(__kk_bytearray_output_stream_to_byte_array(copied))
        #expect(thrown == 0 && copiedBytes == [1, 2, 3])
        state[1] = failure
        let errorChain = __kk_sequence_input_stream_new(__kk_bytearrayinputstream_new(array([7]), &thrown), input(stateRaw))
        let partial = __kk_bytearray_output_stream_new_default()
        #expect(kk_unbox_long(__kk_input_stream_copyTo(errorChain, partial, kk_box_int(1), &thrown)) == 1)
        let partialBytes = try values(__kk_bytearray_output_stream_to_byte_array(partial))
        #expect(thrown == failure && partialBytes == [7])
    }

    @Test(arguments: [false, true])
    func nativeReadBytesIsAWholePrimitiveByteArrayForTypedReflection(nonempty: Bool) throws {
        let expected = nonempty ? [-1, 0, 7] : []
        var thrown = 0
        let memory = __kk_bytearrayinputstream_new(array(expected), &thrown)
        let state = array([0] + expected)
        let callback = __kk_kotlin_source_input_stream(
            unsafeBitCast(ioReadThunk, to: Int.self), state,
            unsafeBitCast(ioFiniteRangeThunk, to: Int.self), state,
            unsafeBitCast(ioNoopThunk, to: Int.self), state,
            unsafeBitCast(ioNoopThunk, to: Int.self), state,
            unsafeBitCast(ioDescriptionThunk, to: Int.self), state)
        let split = nonempty ? 1 : 0
        let sequence = __kk_sequence_input_stream_new(
            __kk_bytearrayinputstream_new(array(Array(expected.prefix(split))), &thrown),
            __kk_bytearrayinputstream_new(array(Array(expected.dropFirst(split))), &thrown))
        let typeID = runtimeStableNominalTypeID(fqName: "kotlin.ByteArray")
        let token = Int(RuntimeTypeTokenEncoding.nominalBase
            | ((typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift))
        for stream in [memory, callback, sequence] {
            let result = __kk_input_stream_readAllBytes(stream, &thrown)
            let producedBytes = try values(result)
            #expect(thrown == 0 && producedBytes == expected)
            #expect(kk_op_is(result, token) == 1, "A declared ByteArray producer must pass the real nominal check")
            let parameter = __kk_kparameter_create_typed(0, runtimeMakeStringRaw("values"),
                runtimeMakeStringRaw("kotlin.ByteArray"), 2, 2, token)
            let function = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 0, closureRaw: 0, arity: 1))
            let callable = kk_callable_ref_tag_kfunction(function, runtimeMakeStringRaw("bytes"),
                runtimeMakeStringRaw("kotlin.ByteArray"), 1, 0)
            let observed = array([0, 0])
            _ = __kk_kcallable_register(callable, unsafeBitCast(ioByteArrayWholeArrayBridge, to: Int.self), observed,
                registerRuntimeObject(RuntimeListBox(elements: [parameter])), registerRuntimeObject(RuntimeListBox(elements: [])),
                1, 0, 0, registerRuntimeObject(RuntimeListBox(elements: [])))
            let legacyList = registerRuntimeObject(RuntimeListBox(elements: expected))
            #expect(kk_op_is(legacyList, token) == 0, "List storage cannot impersonate a primitive ByteArray")
            let invalidMap = registerRuntimeObject(RuntimeMapBox(keys: [parameter], values: [legacyList]))
            #expect(__kk_kcallable_call_by(callable, invalidMap, &thrown) == runtimeNullSentinelInt)
            let exception = try #require(runtimeThrowableBox(from: thrown))
            #expect(exception.exceptionHierarchyFQNames.contains("kotlin.IllegalArgumentException"))
            #expect(try values(observed) == [0, 0], "An incompatible whole-array argument must not reach the invoker")
            thrown = 0
            let map = registerRuntimeObject(RuntimeMapBox(keys: [parameter], values: [result]))
            let returned = __kk_kcallable_call_by(callable, map, &thrown)
            #expect(thrown == 0 && returned == result, "The real typed invoker preserves the whole produced array identity")
            #expect(try values(observed) == [1, 0])
            #expect(try values(returned) == expected)
        }
    }

    @Test func nativeFileChannelWritesActualBytesAndKeepsDescriptorAndRangeFailures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if completed { try? FileManager.default.removeItem(at: directory) }
                else { print("Retained KUU1762 Runtime file proof: " + directory.path) } }
        let file = directory.appendingPathComponent("channel")
        let path = runtimeMakeStringRaw(file.path)
        var thrown = 0
        _ = __kk_native_nio_create_file(path, &thrown)
        try #require(thrown == 0)
        let writer = __kk_native_filechannel_open(path, 2, &thrown)
        try #require(writer >= 0 && thrown == 0)
        defer { var ignored = 0; _ = __kk_io_fs_close(writer, &ignored) }
        let bytes = array([9, 100, 101, -1, 9])
        #expect(__kk_native_filechannel_write(writer, bytes, 1, 3, &thrown) == 3 && thrown == 0)
        #expect(try Data(contentsOf: file) == Data([100, 101, 255]))
        #expect(__kk_native_filechannel_write(writer, bytes, -1, 1, &thrown) == 0 && thrown != 0)
        thrown = 0
        let reader = __kk_native_filechannel_open(path, 1, &thrown)
        try #require(reader >= 0 && thrown == 0)
        defer { var ignored = 0; _ = __kk_io_fs_close(reader, &ignored) }
        let destination = array([9, 9, 9, 9, 9])
        #expect(__kk_io_fs_read(reader, destination, 1, 3, &thrown) == 3 && thrown == 0)
        #expect(try values(destination) == [9, 100, 101, -1, 9])
        #expect(__kk_io_fs_read(reader, destination, 0, 1, &thrown) == 0 && thrown == 0)
        _ = __kk_native_nio_create_file(path, &thrown)
        #expect(thrown != 0)
        completed = true
    }

}
