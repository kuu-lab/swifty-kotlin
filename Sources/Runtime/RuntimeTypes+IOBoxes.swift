import Foundation

protocol RuntimeReaderInputStream: AnyObject {
    func readByte() -> Int
    func available() -> Int
    func close()
}

final class RuntimeBufferedReaderBox {
    private var inputStream: (any RuntimeReaderInputStream)?
    private var upstreamReader: RuntimeBufferedReaderBox?
    private var fileHandle: FileHandle?
    private var pendingData: Data
    /// Offset (from `pendingData.startIndex`) of the first unconsumed byte.
    /// `read()`/`readLine()` advance this cursor instead of removing bytes
    /// from the front of `pendingData` — each front removal would shift every
    /// remaining byte (O(buffer)), turning a full drain quadratic. Consumed
    /// bytes are dropped once per refill, so consumption is amortized O(1).
    private var readOffset: Int
    private var closed: Bool
    private var reachedEOF: Bool
    private let chunkSize: Int

    private var pendingStartIndex: Data.Index {
        pendingData.index(pendingData.startIndex, offsetBy: readOffset)
    }

    private var pendingByteCount: Int {
        pendingData.count - readOffset
    }

    init(fileHandle: FileHandle, chunkSize: Int = 4096) {
        self.fileHandle = fileHandle
        self.pendingData = Data()
        self.readOffset = 0
        self.closed = false
        self.reachedEOF = false
        self.chunkSize = max(1, chunkSize)
    }

    /// Used by `InputStream.bufferedReader()` (STDLIB-IO-FN-007) where the
    /// underlying `InputStream` is in-memory (`ByteArrayInputStream`) — no
    /// `FileHandle` is involved, so the buffer is treated as already at EOF.
    init(data: Data, chunkSize: Int = 4096) {
        self.fileHandle = nil
        self.pendingData = data
        self.readOffset = 0
        self.closed = false
        self.reachedEOF = true
        self.chunkSize = max(1, chunkSize)
    }

    /// Preserve the stream cursor until the first read; reuse the existing
    /// UTF-8 decoder and line-ending handling rather than draining at construction.
    convenience init(inputStream: any RuntimeReaderInputStream) {
        self.init(data: Data())
        self.inputStream = inputStream
        self.reachedEOF = false
    }

    /// Reader handles already provide buffering. Keep a distinct close state
    /// while forwarding reads and closing the wrapped reader transitively.
    convenience init(reader: RuntimeBufferedReaderBox) {
        self.init(data: Data())
        self.upstreamReader = reader
    }

    func readLine() -> String? {
        guard !closed else { return nil }
        if let upstreamReader { return upstreamReader.readLine() }

        while true {
            if let (lineLength, terminatorLength) = locateLineTerminator() {
                let lineStart = pendingStartIndex
                let lineEnd = pendingData.index(lineStart, offsetBy: lineLength)
                readOffset += lineLength + terminatorLength
                return String(decoding: pendingData[lineStart ..< lineEnd], as: UTF8.self)
            }

            if reachedEOF {
                guard pendingByteCount > 0 else { return nil }
                let line = String(decoding: pendingData[pendingStartIndex...], as: UTF8.self)
                pendingData.removeAll(keepingCapacity: false)
                readOffset = 0
                return line
            }

            if !readNextChunk() {
                reachedEOF = true
            }
        }
    }

    func readLines() -> [String] {
        guard !closed else { return [] }
        var remaining: [String] = []
        while let line = readLine() {
            remaining.append(line)
        }
        return remaining
    }

    /// Does NOT close the reader, matching Kotlin's `Reader.readText()`
    /// contract (callers wrap in `use` to release the underlying file handle).
    func readText() -> String {
        guard !closed else { return "" }
        if let upstreamReader { return upstreamReader.readText() }
        var data = pendingData.suffix(from: pendingStartIndex)
        pendingData.removeAll(keepingCapacity: false)
        readOffset = 0
        while !reachedEOF {
            if !readNextChunk() {
                reachedEOF = true
            } else {
                data.append(pendingData)
                pendingData.removeAll(keepingCapacity: false)
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads a single character, returning its Unicode scalar value, or -1 on EOF.
    func read() -> Int {
        guard !closed else { return -1 }
        if let upstreamReader { return upstreamReader.read() }

        while true {
            if pendingByteCount > 0 {
                let byte = pendingData[pendingStartIndex]
                readOffset += 1
                if byte & 0x80 == 0 {
                    return Int(byte)
                }
                var codePoint: UInt32 = 0
                let totalBytes: Int
                if byte & 0xE0 == 0xC0 {
                    totalBytes = 2
                    codePoint = UInt32(byte & 0x1F)
                } else if byte & 0xF0 == 0xE0 {
                    totalBytes = 3
                    codePoint = UInt32(byte & 0x0F)
                } else if byte & 0xF8 == 0xF0 {
                    totalBytes = 4
                    codePoint = UInt32(byte & 0x07)
                } else {
                    // Continuation byte or invalid — return as-is
                    return Int(byte)
                }
                while pendingByteCount < totalBytes - 1 {
                    if reachedEOF { return Int(byte) }
                    if !readNextChunk() { reachedEOF = true }
                }
                if pendingByteCount < totalBytes - 1 { return Int(byte) }
                for _ in 1 ..< totalBytes {
                    let cont = pendingData[pendingStartIndex]
                    readOffset += 1
                    codePoint = (codePoint << 6) | UInt32(cont & 0x3F)
                }
                return Int(codePoint)
            }

            if reachedEOF { return -1 }
            if !readNextChunk() { reachedEOF = true }
        }
    }

    func ready() -> Bool {
        guard !closed else { return false }
        if let upstreamReader { return upstreamReader.ready() }
        if let inputStream { return pendingByteCount > 0 || inputStream.available() > 0 }
        return pendingByteCount > 0 || !reachedEOF
    }

    func close() {
        guard !closed else { return }
        inputStream?.close()
        inputStream = nil
        upstreamReader?.close()
        upstreamReader = nil
        try? fileHandle?.close()
        fileHandle = nil
        pendingData.removeAll(keepingCapacity: false)
        readOffset = 0
        closed = true
    }

    deinit {
        close()
    }

    private func readNextChunk() -> Bool {
        if let inputStream {
            var chunk = Data()
            for _ in 0 ..< chunkSize {
                let byte = inputStream.readByte()
                if byte < 0 { break }
                chunk.append(UInt8(truncatingIfNeeded: byte))
            }
            guard !chunk.isEmpty else { return false }
            dropConsumedPrefix()
            pendingData.append(chunk)
            return true
        }
        guard let fileHandle else { return false }
        guard let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
            return false
        }
        dropConsumedPrefix()
        pendingData.append(chunk)
        return true
    }

    /// Drops already-consumed bytes from the front of `pendingData`, keeping
    /// the buffer bounded to roughly one unread chunk instead of accumulating
    /// every byte the reader has ever seen.
    private func dropConsumedPrefix() {
        guard readOffset > 0 else { return }
        pendingData.removeFirst(readOffset)
        readOffset = 0
    }

    private func locateLineTerminator() -> (lineLength: Int, terminatorLength: Int)? {
        let startIndex = pendingStartIndex
        var index = startIndex
        while index < pendingData.endIndex {
            let byte = pendingData[index]
            if byte == 0x0A {
                return (pendingData.distance(from: startIndex, to: index), 1)
            }
            if byte == 0x0D {
                let nextIndex = pendingData.index(after: index)
                if nextIndex < pendingData.endIndex {
                    let lineLength = pendingData.distance(from: startIndex, to: index)
                    return (lineLength, pendingData[nextIndex] == 0x0A ? 2 : 1)
                }
                if reachedEOF {
                    return (pendingData.distance(from: startIndex, to: index), 1)
                }
                return nil
            }
            index = pendingData.index(after: index)
        }
        return nil
    }
}

class RuntimeInputStreamBox: RuntimeChildReferenceProviding, RuntimeReaderInputStream {
    /// Native stream implementations report I/O failures through the existing ABI.
    var readError: String? { nil }
    private let data: Data
    private let arrayRaw: Int?
    private let end: Int
    private var offset: Int
    private var markPosition: Int
    private var closed: Bool
    private let closeIsNoOp: Bool

    init(data: Data, closeIsNoOp: Bool = false) {
        self.data = data
        self.arrayRaw = nil
        self.end = data.count
        self.closeIsNoOp = closeIsNoOp
        self.offset = 0
        self.markPosition = 0
        self.closed = false
    }

    /// ByteArrayInputStream retains the supplied array, including a ranged
    /// ByteArray.inputStream view. A later caller mutation is observed by read.
    init(arrayRaw: Int, offset: Int, length: Int) {
        self.data = Data()
        self.arrayRaw = arrayRaw
        self.end = offset + length
        self.closeIsNoOp = true
        self.offset = offset
        self.markPosition = offset
        self.closed = false
    }

    var childRefs: [Int] { arrayRaw.map { [$0] } ?? [] }

    private func byte(at index: Int) -> UInt8 {
        guard let arrayRaw else { return data[index] }
        if let array = runtimeArrayBox(from: arrayRaw) { return UInt8(truncatingIfNeeded: array[index]) }
        return UInt8(truncatingIfNeeded: kk_unbox_int(runtimeListBox(from: arrayRaw)?[index] ?? 0))
    }

    func readByte() -> Int {
        guard !closed, offset < end else { return -1 }
        defer { offset += 1 }
        return Int(byte(at: offset))
    }

    func available() -> Int { closed ? 0 : max(0, end - offset) }

    func skip(_ count: Int) -> Int {
        guard !closed else { return 0 }
        let bounded = max(0, min(count, available()))
        offset += bounded
        return bounded
    }

    func readAllBytes() -> [Int] {
        guard !closed else { return [] }
        let values = (offset..<end).map { Int(Int8(bitPattern: byte(at: $0))) }
        offset = end
        return values
    }

    func mark() {
        if closeIsNoOp { markPosition = offset }
    }
    func markSupported() -> Bool { closeIsNoOp }
    func reset() -> Bool {
        guard closeIsNoOp else { return false }
        offset = markPosition
        return true
    }
    func close() {
        if !closeIsNoOp { closed = true }
    }
}

final class RuntimeSequenceInputStreamBox: RuntimeChildReferenceProviding, RuntimeReaderInputStream {
    private var current: Int?
    private var remaining: Int?

    init(first: Int, second: Int) {
        self.current = first
        self.remaining = second
    }

    var childRefs: [Int] { [current, remaining].compactMap { $0 } }

    private func advance(_ outThrown: UnsafeMutablePointer<Int>?) -> Bool {
        if let raw = current {
            _ = __kk_input_stream_close_throwing(raw, outThrown)
            if let outThrown, outThrown.pointee != 0 { return false }
        }
        current = remaining
        remaining = nil
        return true
    }

    func readByte(_ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
        while let raw = current {
            let byte = __kk_input_stream_read(raw, outThrown)
            if let outThrown, outThrown.pointee != 0 { return -1 }
            if byte != -1 { return byte }
            if !advance(outThrown) { return -1 }
        }
        return -1
    }

    func readRange(_ bytes: Int, _ offset: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard current != nil else { return -1 }
        let size = runtimeArrayBox(from: bytes)?.count ?? runtimeListBox(from: bytes)?.count
        guard let size, offset >= 0, count >= 0, offset <= size - count else {
            outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(message: "SequenceInputStream offset/count out of bounds")
            return -1
        }
        if count == 0 { return 0 }
        while let raw = current {
            let copied = __kk_input_stream_read_range(raw, bytes, offset, count, outThrown)
            if let outThrown, outThrown.pointee != 0 { return -1 }
            // SequenceInputStream does not fill a request across streams.
            if copied != -1 { return copied }
            if !advance(outThrown) { return -1 }
        }
        return -1
    }

    func readByte() -> Int { readByte(nil) }

    func available(_ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
        current.map { __kk_input_stream_available_throwing($0, outThrown) } ?? 0
    }

    func available() -> Int { available(nil) }

    func readAllBytes(_ outThrown: UnsafeMutablePointer<Int>? = nil) -> [Int] {
        var result: [Int] = []
        while true {
            let byte = readByte(outThrown)
            if let outThrown, outThrown.pointee != 0 { return [] }
            if byte == -1 { return result }
            result.append(Int(Int8(truncatingIfNeeded: byte)))
        }
    }

    func close() { close(nil) }

    func close(_ outThrown: UnsafeMutablePointer<Int>? = nil) {
        let streams = childRefs
        current = nil
        remaining = nil
        var firstFailure = 0
        for raw in streams {
            var failure = 0
            _ = __kk_input_stream_close_throwing(raw, &failure)
            if failure != 0 {
                if firstFailure == 0 { firstFailure = failure }
                else if failure != firstFailure { _ = __kk_throwable_appendSuppressed(firstFailure, failure) }
            }
        }
        outThrown?.pointee = firstFailure
    }
}

protocol RuntimeOutputStreamSink: AnyObject {
    func write(_ data: Data) throws
    func flush() throws
    func close()
    func closeThrowing() throws
}

extension RuntimeOutputStreamSink {
    func closeThrowing() throws { close() }
}

final class RuntimeFileHandleOutputStreamSink: RuntimeOutputStreamSink {
    private let fileHandle: FileHandle
    private var closed: Bool

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        self.closed = false
    }

    func write(_ data: Data) throws {
        guard !closed else { return }
        try fileHandle.write(contentsOf: data)
    }

    func flush() throws {
        guard !closed else { return }
        try fileHandle.synchronize()
    }

    func close() {
        guard !closed else { return }
        try? fileHandle.close()
        closed = true
    }

    func closeThrowing() throws {
        guard !closed else { return }
        defer { closed = true }
        try fileHandle.close()
    }

}

/// A Kotlin throwable rethrown through the Swift `Error` channel by a
/// callback-backed stream sink. `thrownRaw` is the original Kotlin throwable
/// handle; the `__kk_*_stream_*` bridges write it to `outThrown` unchanged so
/// the Kotlin caller observes the original exception rather than a synthesized
/// `IOException`.
struct RuntimeKotlinThrownError: Error {
    let thrownRaw: Int
}

/// Each callback is a KSwiftK closure stored as a (fnPtr, closureRaw) pair:
/// `write: (ByteArray) -> Unit` is invoked through the collection-HOF
/// entry-point convention and `flush`/`close: () -> Unit` through the closure
/// thunk convention — the same conventions the `__kk_synchronized` /
/// `kk_worker_execute` bridges use. The `write` argument is passed as a
/// `RuntimeArrayBox`, which is the runtime representation of `ByteArray`.
final class RuntimeKotlinOutputStreamSink: RuntimeOutputStreamSink {
    private let writeFnPtr: Int
    private let writeClosureRaw: Int
    private let flushFnPtr: Int
    private let flushClosureRaw: Int
    private let closeFnPtr: Int
    private let closeClosureRaw: Int

    init(
        writeFnPtr: Int,
        writeClosureRaw: Int,
        flushFnPtr: Int,
        flushClosureRaw: Int,
        closeFnPtr: Int,
        closeClosureRaw: Int
    ) {
        self.writeFnPtr = writeFnPtr
        self.writeClosureRaw = writeClosureRaw
        self.flushFnPtr = flushFnPtr
        self.flushClosureRaw = flushClosureRaw
        self.closeFnPtr = closeFnPtr
        self.closeClosureRaw = closeClosureRaw
    }

    func write(_ data: Data) throws {
        let arrayBox = RuntimeArrayBox(length: data.count)
        for (index, byte) in data.enumerated() {
            arrayBox[index] = Int(Int8(bitPattern: byte))
        }
        let arrayRaw = registerRuntimeObject(arrayBox)
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(
            fnPtr: writeFnPtr,
            closureRaw: writeClosureRaw,
            value: arrayRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            throw RuntimeKotlinThrownError(thrownRaw: thrown)
        }
    }

    func flush() throws {
        var thrown = 0
        _ = runtimeInvokeClosureThunk(
            fnPtr: flushFnPtr,
            closureRaw: flushClosureRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            throw RuntimeKotlinThrownError(thrownRaw: thrown)
        }
    }

    func close() { try? closeThrowing() }

    func closeThrowing() throws {
        var thrown = 0
        _ = runtimeInvokeClosureThunk(fnPtr: closeFnPtr, closureRaw: closeClosureRaw, outThrown: &thrown)
        if thrown != 0 { throw RuntimeKotlinThrownError(thrownRaw: thrown) }
    }
}

final class RuntimeOutputStreamBox: RuntimeChildReferenceProviding {
    private let sink: RuntimeOutputStreamSink

    init(fileHandle: FileHandle) {
        self.sink = RuntimeFileHandleOutputStreamSink(fileHandle: fileHandle)
    }

    init(sink: RuntimeOutputStreamSink) {
        self.sink = sink
    }

    func writeByte(_ value: Int) throws {
        let byte = UInt8(truncatingIfNeeded: value)
        try sink.write(Data([byte]))
    }

    func writeBytes(_ values: [Int]) throws {
        let bytes = values.map { UInt8(truncatingIfNeeded: $0) }
        try sink.write(Data(bytes))
    }

    func write(_ data: Data) throws {
        try sink.write(data)
    }

    func flush() throws {
        try sink.flush()
    }

    func close() { sink.close() }

    func closeThrowing() throws { try sink.closeThrowing() }

    /// Return false for an ordinary byte stream so the caller can validate
    /// and copy its range. Callback streams preserve source validation order.
    func writeKotlinRange(_ array: Int, offset: Int, count: Int) throws -> Bool {
        guard let callback = sink as? RuntimeKotlinRangeOutputStreamSink else { return false }
        try callback.writeRange(array, offset: offset, count: count)
        return true
    }

    var childRefs: [Int] { (sink as? RuntimeChildReferenceProviding)?.childRefs ?? [] }

    var hasKotlinDescription: Bool { sink is RuntimeKotlinRangeOutputStreamSink }

    func kotlinDescription(_ thrown: UnsafeMutablePointer<Int>?) -> Int? {
        (sink as? RuntimeKotlinRangeOutputStreamSink)?.kotlinDescription(thrown)
    }

    var byteArraySink: RuntimeByteArrayOutputStreamSink? { sink as? RuntimeByteArrayOutputStreamSink }

}

protocol RuntimeJavaWriter: AnyObject {
    func write(_ text: String) throws
    func flush() throws
    func closeThrowing() throws
}

final class RuntimeStringWriterBox: RuntimeJavaWriter {
    private let builder: RuntimeStringBuilderBox
    let bufferRaw: Int

    init(builder: RuntimeStringBuilderBox, bufferRaw: Int) {
        self.builder = builder
        self.bufferRaw = bufferRaw
    }

    func write(_ text: String) {
        builder.ensureCapacity(builder.units.count + text.utf16.count)
        runtimeAppendKotlinUTF16CodeUnits(of: text, to: &builder.units)
    }

    func flush() {}

    func closeThrowing() throws {}

    func stringValue() -> String { builder.stringValue }
}

final class RuntimeBufferedWriterBox: RuntimeJavaWriter {
    private let fileHandle: FileHandle?
    private let stream: RuntimeOutputStreamBox?
    private let upstreamWriter: (any RuntimeJavaWriter)?
    private let charsetTag: CharsetTag?
    private var buffer: Data
    private var pendingText: String
    private let bufferSize: Int
    private let encoding: String.Encoding
    private var closed: Bool

    init(fileHandle: FileHandle, bufferSize: Int = 8192, encoding: String.Encoding = .utf8) {
        self.fileHandle = fileHandle
        self.stream = nil
        self.upstreamWriter = nil
        self.charsetTag = nil
        self.buffer = Data()
        self.pendingText = ""
        self.bufferSize = max(1, bufferSize)
        self.encoding = encoding
        self.closed = false
    }

    init(stream: RuntimeOutputStreamBox, charsetTag: CharsetTag, bufferSize: Int = 8192) {
        self.fileHandle = nil
        self.stream = stream
        self.upstreamWriter = nil
        self.charsetTag = charsetTag
        self.buffer = Data()
        self.pendingText = ""
        self.bufferSize = max(1, bufferSize)
        self.encoding = .utf8
        self.closed = false
    }

    init(writer: any RuntimeJavaWriter, bufferSize: Int = 8192) {
        self.fileHandle = nil
        self.stream = nil
        self.upstreamWriter = writer
        self.charsetTag = nil
        self.buffer = Data()
        self.pendingText = ""
        self.bufferSize = max(1, bufferSize)
        self.encoding = .utf8
        self.closed = false
    }

    func write(_ text: String) throws {
        guard !closed else { throw RuntimeKotlinThrownError(thrownRaw: runtimeAllocateIOException(message: "Stream closed")) }
        if upstreamWriter != nil {
            pendingText.append(text)
            if pendingText.utf16.count >= bufferSize {
                try flushBuffer()
            }
            return
        }
        let data: Data
        if let charsetTag {
            data = Data(runtimeCharsetEncodedBytes(text, tag: charsetTag).map { UInt8(truncatingIfNeeded: $0) })
        } else {
            guard let encoded = text.data(using: encoding) ?? text.data(using: .utf8) else { return }
            data = encoded
        }
        buffer.append(data)
        if buffer.count >= bufferSize {
            try flushBuffer()
        }
    }

    func newLine() throws {
        try write("\n")
    }

    func flush() throws {
        guard !closed else { throw RuntimeKotlinThrownError(thrownRaw: runtimeAllocateIOException(message: "Stream closed")) }
        try flushBuffer()
        if let upstreamWriter { try upstreamWriter.flush() }
        else if let stream { try stream.flush() }
        else { try fileHandle?.synchronize() }
    }

    func close() { try? closeThrowing() }

    func closeThrowing() throws {
        guard !closed else { return }
        defer { closed = true }
        do { try flush() }
        catch {
            // Close the underlying stream even if encoding/flush failed.
            try? stream?.closeThrowing()
            try? fileHandle?.close()
            try? upstreamWriter?.closeThrowing()
            throw error
        }
        if let upstreamWriter { try upstreamWriter.closeThrowing() }
        else if let stream { try stream.closeThrowing() }
        else { try fileHandle?.close() }
    }

    deinit {
        close()
    }

    private func flushBuffer() throws {
        if let upstreamWriter {
            guard !pendingText.isEmpty else { return }
            try upstreamWriter.write(pendingText)
            pendingText = ""
            return
        }
        guard !buffer.isEmpty else { return }
        if let stream { try stream.write(buffer) }
        else { try fileHandle?.write(contentsOf: buffer) }
        buffer.removeAll(keepingCapacity: true)
    }
}
