import Foundation

// MARK: - BufferedReader (STDLIB-567)

/// Runtime box for `java.io.BufferedReader` returned by `File.bufferedReader()`.
/// Wraps a streaming file reader, supporting `readLine()` and `readLines()`.
final class RuntimeBufferedReaderBox {
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

    /// Index of the first unconsumed byte in `pendingData`.
    private var pendingStartIndex: Data.Index {
        pendingData.index(pendingData.startIndex, offsetBy: readOffset)
    }

    /// Bytes buffered but not yet consumed.
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

    /// Creates a `BufferedReader` backed by an already-loaded `Data` buffer.
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

    /// Returns the next line, or `nil` when all lines have been consumed.
    func readLine() -> String? {
        guard !closed else { return nil }

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

    /// Returns all remaining lines as an array.
    func readLines() -> [String] {
        guard !closed else { return [] }
        var remaining: [String] = []
        while let line = readLine() {
            remaining.append(line)
        }
        return remaining
    }

    /// Reads the remaining content of the reader into a single `String`
    /// (STDLIB-IO-FN-033). Mirrors `kotlin.io.readText()`: drains any buffered
    /// bytes and then reads the underlying stream to EOF, decoding the
    /// accumulated bytes as UTF-8. Returns an empty string if the reader is
    /// already closed or has nothing left to read. Does NOT close the reader,
    /// matching Kotlin's `Reader.readText()` contract (callers wrap in `use`
    /// to release the underlying file handle).
    func readText() -> String {
        guard !closed else { return "" }
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

        while true {
            if pendingByteCount > 0 {
                let byte = pendingData[pendingStartIndex]
                readOffset += 1
                // Fast path: ASCII byte
                if byte & 0x80 == 0 {
                    return Int(byte)
                }
                // Multi-byte UTF-8: put back and decode
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
                // Ensure we have enough continuation bytes
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

    /// Returns true if data is available to be read without blocking (buffered bytes exist or not EOF).
    func ready() -> Bool {
        guard !closed else { return false }
        return pendingByteCount > 0 || !reachedEOF
    }

    func close() {
        guard !closed else { return }
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

// MARK: - InputStream / OutputStream (STDLIB-IO-092)

final class RuntimeInputStreamBox {
    private let data: Data
    private var offset: Int
    private var closed: Bool

    init(data: Data) {
        self.data = data
        self.offset = 0
        self.closed = false
    }

    func readByte() -> Int {
        guard !closed else { return -1 }
        guard offset < data.count else { return -1 }
        defer { offset += 1 }
        return Int(data[offset])
    }

    func available() -> Int {
        guard !closed else { return 0 }
        return max(0, data.count - offset)
    }

    func skip(_ count: Int) -> Int {
        guard !closed else { return 0 }
        let bounded = max(0, min(count, available()))
        offset += bounded
        return bounded
    }

    func read(into list: RuntimeListBox) -> Int {
        guard !closed else { return -1 }
        let writableCount = min(list.count, available())
        guard writableCount > 0 else { return -1 }
        for index in 0 ..< writableCount {
            list[index] = Int(Int8(bitPattern: data[offset + index]))
        }
        offset += writableCount
        return writableCount
    }

    /// Reads all remaining bytes from the stream as a list of signed Int values
    /// in the range [-128, 127] (matching `kotlin.ByteArray` element semantics).
    /// Advances the read cursor to the end of the underlying buffer.  When the
    /// stream is closed or already at EOF, returns an empty list.
    /// Used by `InputStream.readBytes()` (STDLIB-IO-FN-029).
    func readAllBytes() -> [Int] {
        guard !closed else { return [] }
        let remaining = max(0, data.count - offset)
        guard remaining > 0 else { return [] }
        var elements: [Int] = []
        elements.reserveCapacity(remaining)
        for index in 0 ..< remaining {
            elements.append(Int(Int8(bitPattern: data[offset + index])))
        }
        offset += remaining
        return elements
    }

    func mark(readLimit: Int) {
        // FileInputStream does not support mark/reset; this is a no-op.
    }

    func markSupported() -> Bool { false }

    /// Attempts a reset.  Returns `false` when mark/reset is not supported
    /// (matching JVM FileInputStream behaviour — callers must raise IOException).
    func reset() -> Bool { false }

    func close() {
        closed = true
    }

    /// Drain remaining bytes (after the current `offset`) so they can be
    /// handed to a `BufferedReader` constructed by
    /// `InputStream.bufferedReader()` (STDLIB-IO-FN-007). Mirrors what the
    /// JVM does: wrapping an `InputStream` in an `InputStreamReader` reads
    /// from the *current* position onwards. Advances the offset to the end
    /// because callers should treat the stream as fully consumed.
    func drainRemaining() -> Data {
        guard !closed else { return Data() }
        let remaining = data.suffix(from: data.startIndex.advanced(by: offset))
        offset = data.count
        return Data(remaining)
    }
}

/// Runtime box for `java.io.SequenceInputStream` — chains two InputStreams.
final class RuntimeSequenceInputStreamBox {
    private var first: RuntimeInputStreamBox?
    private var second: RuntimeInputStreamBox?
    private var closed: Bool

    init(first: RuntimeInputStreamBox, second: RuntimeInputStreamBox) {
        self.first = first
        self.second = second
        self.closed = false
    }

    func readByte() -> Int {
        guard !closed else { return -1 }
        if let s1 = first {
            let b = s1.readByte()
            if b != -1 { return b }
            // first stream exhausted — move to second
            s1.close()
            first = nil
        }
        return second?.readByte() ?? -1
    }

    func available() -> Int {
        guard !closed else { return 0 }
        return first?.available() ?? 0
    }

    /// Reads all remaining bytes across both chained streams.  Drains `first`
    /// fully, then drains `second`.  Used by `InputStream.readBytes()`
    /// (STDLIB-IO-FN-029) when the receiver is a SequenceInputStream.
    func readAllBytes() -> [Int] {
        guard !closed else { return [] }
        var elements: [Int] = []
        if let s1 = first {
            elements.append(contentsOf: s1.readAllBytes())
            s1.close()
            first = nil
        }
        if let s2 = second {
            elements.append(contentsOf: s2.readAllBytes())
        }
        return elements
    }

    func close() {
        guard !closed else { return }
        first?.close()
        second?.close()
        first = nil
        second = nil
        closed = true
    }
}

// MARK: - RuntimeOutputStreamSink (STDLIB-IO-ENC-FN-002)

/// Pluggable back-end for `RuntimeOutputStreamBox`.  Concrete implementations
/// may wrap a real `FileHandle` (normal file-backed streams) or provide a
/// transforming layer such as the Base64-encoding stream.
protocol RuntimeOutputStreamSink: AnyObject {
    func write(_ data: Data) throws
    func flush() throws
    func close()
}

/// Concrete `RuntimeOutputStreamSink` backed by a `FileHandle`.
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

    var underlyingFileHandle: FileHandle { fileHandle }
}

/// A Kotlin throwable rethrown through the Swift `Error` channel by a
/// callback-backed stream sink. `thrownRaw` is the original Kotlin throwable
/// handle; the `__kk_*_stream_*` bridges write it to `outThrown` unchanged so
/// the Kotlin caller observes the original exception rather than a synthesized
/// `IOException`.
struct RuntimeKotlinThrownError: Error {
    let thrownRaw: Int
}

/// `RuntimeOutputStreamSink` that forwards write/flush/close into Kotlin
/// lambdas captured by `kotlinx.io.Sink.asOutputStream()` (KSP-1553).
///
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

    func close() {
        // `close()` has no thrown channel (`__kk_output_stream_close` takes no
        // outThrown), so a throwable raised by the close callback is dropped,
        // matching the file-backed sink's `try? fileHandle.close()` swallow.
        var thrown = 0
        _ = runtimeInvokeClosureThunk(
            fnPtr: closeFnPtr,
            closureRaw: closeClosureRaw,
            outThrown: &thrown
        )
    }
}

final class RuntimeOutputStreamBox {
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

    func close() {
        sink.close()
    }

    var underlyingFileHandle: FileHandle? {
        (sink as? RuntimeFileHandleOutputStreamSink)?.underlyingFileHandle
    }

    /// Creates a `RuntimeBufferedWriterBox` wrapping the underlying file handle.
    /// Returns `nil` when the sink is not file-handle backed (e.g. an encoding
    /// stream).  STDLIB-IO-FN-009.
    func makeBufferedWriter(encoding: String.Encoding) -> RuntimeBufferedWriterBox? {
        guard let fileHandle = underlyingFileHandle else {
            return nil
        }
        let writer = RuntimeBufferedWriterBox(fileHandle: fileHandle, encoding: encoding)
        return writer
    }
}

// MARK: - BufferedWriter (STDLIB-IO-091/093)

/// Runtime box for `java.io.BufferedWriter` returned by `File.bufferedWriter()`.
/// Wraps a streaming file writer, supporting `write()`, `newLine()`, `flush()`, and `close()`.
final class RuntimeBufferedWriterBox {
    private let fileHandle: FileHandle
    private var buffer: Data
    private let bufferSize: Int
    private let encoding: String.Encoding
    private var closed: Bool

    init(fileHandle: FileHandle, bufferSize: Int = 8192, encoding: String.Encoding = .utf8) {
        self.fileHandle = fileHandle
        self.buffer = Data()
        self.bufferSize = max(1, bufferSize)
        self.encoding = encoding
        self.closed = false
    }

    /// Writes a string to the buffer, flushing when full.
    func write(_ text: String) throws {
        guard !closed else { return }
        guard let data = text.data(using: encoding) ?? text.data(using: .utf8) else { return }
        buffer.append(data)
        if buffer.count >= bufferSize {
            try flushBuffer()
        }
    }

    /// Writes a system line separator.
    func newLine() throws {
        try write("\n")
    }

    /// Flushes buffered data to the file.
    func flush() throws {
        guard !closed else { return }
        try flushBuffer()
        try fileHandle.synchronize()
    }

    func close() {
        guard !closed else { return }
        try? flushBuffer()
        try? fileHandle.close()
        closed = true
    }

    deinit {
        close()
    }

    private func flushBuffer() throws {
        guard !buffer.isEmpty else { return }
        try fileHandle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}
