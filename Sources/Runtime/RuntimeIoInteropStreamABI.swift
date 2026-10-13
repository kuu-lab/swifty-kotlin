import Foundation

private func ioInteropInput(_ raw: Int) -> RuntimeInputStreamBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeInputStreamBox.self)
}

private func ioInteropOutput(_ raw: Int) -> RuntimeOutputStreamBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeOutputStreamBox.self)
}

@_cdecl("__kk_input_stream_read_range")
public func __kk_input_stream_read_range(
    _ stream: Int, _ bytes: Int, _ offset: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if let callback = runtimeKotlinInputStream(from: stream) {
        // Kotlin validates the original arguments after checking Source.closed.
        return callback.readRange(bytes, offset, count, outThrown)
    }
    if let pointer = UnsafeMutableRawPointer(bitPattern: stream),
       let sequence = tryCast(pointer, to: RuntimeSequenceInputStreamBox.self) {
        return sequence.readRange(bytes, offset, count, outThrown)
    }
    guard let input = ioInteropInput(stream) else {
        fatalError("KSwiftK panic: invalid InputStream handle")
    }
    let array = runtimeArrayBox(from: bytes)
    let list = runtimeListBox(from: bytes)
    guard let size = array?.count ?? list?.count else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray")
        return -1
    }
    guard offset >= 0, count >= 0, offset <= size - count else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(message: "offset/count out of bounds")
        return -1
    }
    if input.available() == 0 { return -1 }
    if count == 0 { return 0 }
    var copied = 0
    while copied < count {
        let value = input.readByte()
        if value == -1 { break }
        let byte = Int(Int8(truncatingIfNeeded: value))
        if let array { array[offset + copied] = byte }
        else { list?[offset + copied] = byte }
        copied += 1
    }
    return copied == 0 ? -1 : copied
}

@_cdecl("__kk_output_stream_write_range")
public func __kk_output_stream_write_range(
    _ stream: Int, _ bytes: Int, _ offset: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let output = ioInteropOutput(stream) else {
        fatalError("KSwiftK panic: invalid OutputStream handle")
    }
    do {
        if try output.writeKotlinRange(bytes, offset: offset, count: count) { return 0 }
        let array = runtimeArrayBox(from: bytes)
        let list = runtimeListBox(from: bytes)
        guard let size = array?.count ?? list?.count else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray")
            return 0
        }
        guard offset >= 0, count >= 0, offset <= size - count else {
            outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(message: "offset/count out of bounds")
            return 0
        }
        let values = (offset ..< offset + count).map { array?[$0] ?? kk_unbox_int(list?[$0] ?? 0) }
        try output.writeBytes(values)
    } catch let error as RuntimeKotlinThrownError {
        outThrown?.pointee = error.thrownRaw
    } catch {
        outThrown?.pointee = runtimeAllocateIOException(message: error.localizedDescription)
    }
    return 0
}

// The original one-word exported available/close functions remain untouched.
// New source declarations select these bridges to propagate callback errors.
@_cdecl("__kk_input_stream_available_throwing")
public func __kk_input_stream_available_throwing(_ stream: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if let callback = runtimeKotlinInputStream(from: stream) { return callback.available(outThrown) }
    if let pointer = UnsafeMutableRawPointer(bitPattern: stream),
       let sequence = tryCast(pointer, to: RuntimeSequenceInputStreamBox.self) { return sequence.available(outThrown) }
    return __kk_input_stream_available(stream)
}

@_cdecl("__kk_input_stream_close_throwing")
public func __kk_input_stream_close_throwing(_ stream: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if let callback = runtimeKotlinInputStream(from: stream) {
        callback.close(outThrown)
        return 0
    }
    if let pointer = UnsafeMutableRawPointer(bitPattern: stream),
       let sequence = tryCast(pointer, to: RuntimeSequenceInputStreamBox.self) { sequence.close(outThrown); return 0 }
    return __kk_input_stream_close(stream)
}

@_cdecl("__kk_output_stream_close_throwing")
public func __kk_output_stream_close_throwing(_ stream: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let output = ioInteropOutput(stream) else { fatalError("KSwiftK panic: invalid OutputStream handle") }
    do { try output.closeThrowing() }
    catch let error as RuntimeKotlinThrownError { outThrown?.pointee = error.thrownRaw }
    catch { outThrown?.pointee = runtimeAllocateIOException(message: error.localizedDescription) }
    return 0
}

// Retain the old one-word writer close ABI for old callers. Source bindings
// use a throwing channel so callback-backed stream close errors survive.
@_cdecl("__kk_buffered_writer_close_throwing")
public func __kk_buffered_writer_close_throwing(_ writer: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let pointer = UnsafeMutableRawPointer(bitPattern: writer),
          let box = tryCast(pointer, to: RuntimeBufferedWriterBox.self) else {
        fatalError("KSwiftK panic: invalid BufferedWriter handle")
    }
    do { try box.closeThrowing() }
    catch let failure as RuntimeKotlinThrownError { outThrown?.pointee = failure.thrownRaw }
    catch { outThrown?.pointee = runtimeAllocateIOException(message: error.localizedDescription) }
    return 0
}

// Existing single-word SequenceInputStream exports remain for old callers.
@_cdecl("__kk_sequence_input_stream_available_throwing")
public func __kk_sequence_input_stream_available_throwing(_ stream: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    __kk_input_stream_available_throwing(stream, outThrown)
}
@_cdecl("__kk_sequence_input_stream_close_throwing")
public func __kk_sequence_input_stream_close_throwing(_ stream: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    __kk_input_stream_close_throwing(stream, outThrown)
}
