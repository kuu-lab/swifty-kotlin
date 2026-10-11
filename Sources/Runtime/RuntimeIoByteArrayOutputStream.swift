import Foundation

/// Foreign OutputStream storage for the JDK in-memory producer used by the
/// unchanged upstream stream suites. Snapshots never share mutable storage;
/// close/flush are no-ops as specified for ByteArrayOutputStream.
final class RuntimeByteArrayOutputStreamSink: RuntimeOutputStreamSink {
    private(set) var bytes = Data()
    init(capacity: Int) { bytes.reserveCapacity(capacity) }
    func write(_ data: Data) { bytes.append(data) }
    func flush() {}
    func close() {}
    func reset() { bytes.removeAll(keepingCapacity: true) }
}

private func byteArrayOutput(_ raw: Int) -> RuntimeByteArrayOutputStreamSink {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw),
          let stream = tryCast(pointer, to: RuntimeOutputStreamBox.self),
          let sink = stream.byteArraySink else { fatalError("KSwiftK panic: invalid ByteArrayOutputStream handle") }
    return sink
}

@_cdecl("__kk_bytearray_output_stream_new_default")
public func __kk_bytearray_output_stream_new_default() -> Int {
    runtimeRegisterIoStream(RuntimeOutputStreamBox(sink: RuntimeByteArrayOutputStreamSink(capacity: 32)), fqName: "java.io.ByteArrayOutputStream", input: false)
}

@_cdecl("__kk_bytearray_output_stream_new")
public func __kk_bytearray_output_stream_new(_ capacity: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard capacity >= 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Negative initial size: \(capacity)")
        return 0
    }
    return runtimeRegisterIoStream(RuntimeOutputStreamBox(sink: RuntimeByteArrayOutputStreamSink(capacity: capacity)), fqName: "java.io.ByteArrayOutputStream", input: false)
}

@_cdecl("__kk_bytearray_output_stream_to_byte_array")
public func __kk_bytearray_output_stream_to_byte_array(_ stream: Int) -> Int {
    runtimeMakeArrayRaw(byteArrayOutput(stream).bytes.map { Int(Int8(bitPattern: $0)) })
}

@_cdecl("__kk_bytearray_output_stream_reset")
public func __kk_bytearray_output_stream_reset(_ stream: Int) -> Int { byteArrayOutput(stream).reset(); return 0 }

@_cdecl("__kk_bytearray_output_stream_size")
public func __kk_bytearray_output_stream_size(_ stream: Int) -> Int { byteArrayOutput(stream).bytes.count }

@_cdecl("__kk_bytearray_output_stream_to_string")
public func __kk_bytearray_output_stream_to_string(_ stream: Int) -> Int {
    __kk_bytearray_decodeToString_charset(__kk_bytearray_output_stream_to_byte_array(stream), 0)
}
