import Foundation

/// Foreign InputStream storage whose operations delegate into Kotlin Source.
/// Construction performs no read and owns no independent closed flag.
final class RuntimeKotlinInputStreamBox: RuntimeChildReferenceProviding {
    let readFn: Int
    let readClosure: Int
    let rangeFn: Int
    let rangeClosure: Int
    let availableFn: Int
    let availableClosure: Int
    let closeFn: Int
    let closeClosure: Int
    let descriptionFn: Int
    let descriptionClosure: Int

    init(readFn: Int, readClosure: Int, rangeFn: Int, rangeClosure: Int,
         availableFn: Int, availableClosure: Int, closeFn: Int, closeClosure: Int,
         descriptionFn: Int, descriptionClosure: Int) {
        self.readFn = readFn
        self.readClosure = readClosure
        self.rangeFn = rangeFn
        self.rangeClosure = rangeClosure
        self.availableFn = availableFn
        self.availableClosure = availableClosure
        self.closeFn = closeFn
        self.closeClosure = closeClosure
        self.descriptionFn = descriptionFn
        self.descriptionClosure = descriptionClosure
    }

    var childRefs: [Int] { [readClosure, rangeClosure, availableClosure, closeClosure, descriptionClosure].filter { $0 != 0 } }

    func read(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
        kk_unbox_int(runtimeInvokeClosureThunk(fnPtr: readFn, closureRaw: readClosure, outThrown: outThrown))
    }

    func readRange(_ data: Int, _ offset: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
        kk_unbox_int(runtimeInvokeCollectionLambda3(
            fnPtr: rangeFn, closureRaw: rangeClosure, arg1: data,
            arg2: offset, arg3: count, outThrown: outThrown))
    }

    func available(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
        kk_unbox_int(runtimeInvokeClosureThunk(fnPtr: availableFn, closureRaw: availableClosure, outThrown: outThrown))
    }

    func kotlinDescription(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
        runtimeInvokeClosureThunk(fnPtr: descriptionFn, closureRaw: descriptionClosure, outThrown: outThrown)
    }

    func close(_ outThrown: UnsafeMutablePointer<Int>?) {
        _ = runtimeInvokeClosureThunk(fnPtr: closeFn, closureRaw: closeClosure, outThrown: outThrown)
    }
}

func runtimeKotlinInputStream(from raw: Int) -> RuntimeKotlinInputStreamBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeKotlinInputStreamBox.self)
}

@_cdecl("__kk_kotlin_source_input_stream")
public func __kk_kotlin_source_input_stream(
    _ readFn: Int, _ readClosure: Int, _ rangeFn: Int, _ rangeClosure: Int,
    _ availableFn: Int, _ availableClosure: Int, _ closeFn: Int, _ closeClosure: Int,
    _ descriptionFn: Int, _ descriptionClosure: Int
) -> Int {
    runtimeRegisterIoStream(RuntimeKotlinInputStreamBox(
        readFn: readFn, readClosure: readClosure, rangeFn: rangeFn, rangeClosure: rangeClosure,
        availableFn: availableFn, availableClosure: availableClosure, closeFn: closeFn, closeClosure: closeClosure,
        descriptionFn: descriptionFn, descriptionClosure: descriptionClosure), fqName: "java.io.InputStream", input: true)
}

/// Range callbacks see the original ByteArray and arguments, preserving the
/// upstream closed-check-before-bounds order and the segment transaction.
final class RuntimeKotlinRangeOutputStreamSink: RuntimeOutputStreamSink, RuntimeChildReferenceProviding {
    let writeFn: Int
    let writeClosure: Int
    let flushFn: Int
    let flushClosure: Int
    let closeFn: Int
    let closeClosure: Int
    let descriptionFn: Int
    let descriptionClosure: Int

    init(writeFn: Int, writeClosure: Int, flushFn: Int, flushClosure: Int, closeFn: Int, closeClosure: Int,
         descriptionFn: Int, descriptionClosure: Int) {
        self.writeFn = writeFn
        self.writeClosure = writeClosure
        self.flushFn = flushFn
        self.flushClosure = flushClosure
        self.closeFn = closeFn
        self.closeClosure = closeClosure
        self.descriptionFn = descriptionFn
        self.descriptionClosure = descriptionClosure
    }

    var childRefs: [Int] { [writeClosure, flushClosure, closeClosure, descriptionClosure].filter { $0 != 0 } }

    func kotlinDescription(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
        runtimeInvokeClosureThunk(fnPtr: descriptionFn, closureRaw: descriptionClosure, outThrown: outThrown)
    }

    func writeRange(_ data: Int, offset: Int, count: Int) throws {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda3(fnPtr: writeFn, closureRaw: writeClosure,
            arg1: data, arg2: offset, arg3: count, outThrown: &thrown)
        if thrown != 0 { throw RuntimeKotlinThrownError(thrownRaw: thrown) }
    }

    func write(_ data: Data) throws {
        let array = RuntimeArrayBox(length: data.count)
        for (index, byte) in data.enumerated() { array[index] = Int(Int8(bitPattern: byte)) }
        try writeRange(registerRuntimeObject(array), offset: 0, count: data.count)
    }

    func flush() throws {
        var thrown = 0
        _ = runtimeInvokeClosureThunk(fnPtr: flushFn, closureRaw: flushClosure, outThrown: &thrown)
        if thrown != 0 { throw RuntimeKotlinThrownError(thrownRaw: thrown) }
    }

    func close() { try? closeThrowing() }

    func closeThrowing() throws {
        var thrown = 0
        _ = runtimeInvokeClosureThunk(fnPtr: closeFn, closureRaw: closeClosure, outThrown: &thrown)
        if thrown != 0 { throw RuntimeKotlinThrownError(thrownRaw: thrown) }
    }
}

@_cdecl("__kk_kotlin_sink_output_stream_range")
public func __kk_kotlin_sink_output_stream_range(
    _ writeFn: Int, _ writeClosure: Int, _ flushFn: Int, _ flushClosure: Int, _ closeFn: Int, _ closeClosure: Int,
    _ descriptionFn: Int, _ descriptionClosure: Int
) -> Int {
    runtimeRegisterIoStream(RuntimeOutputStreamBox(sink: RuntimeKotlinRangeOutputStreamSink(
        writeFn: writeFn, writeClosure: writeClosure, flushFn: flushFn, flushClosure: flushClosure,
        closeFn: closeFn, closeClosure: closeClosure,
        descriptionFn: descriptionFn, descriptionClosure: descriptionClosure)), fqName: "java.io.OutputStream", input: false)
}

/// Typed InputStream/OutputStream calls have a thrown slot. The existing Any
/// override registry reuses this entry without changing public Any ABI; its
/// pre-existing erased exception policy is documented separately.
@_cdecl("__kk_io_stream_to_string")
public func __kk_io_stream_to_string(_ stream: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if let input = runtimeKotlinInputStream(from: stream) { return input.kotlinDescription(outThrown) }
    if let pointer = UnsafeMutableRawPointer(bitPattern: stream),
       let output = tryCast(pointer, to: RuntimeOutputStreamBox.self),
       let result = output.kotlinDescription(outThrown) { return result }
    return runtimeMakeStringRaw("java.io.Stream@" + String(UInt(bitPattern: stream), radix: 16))
}
