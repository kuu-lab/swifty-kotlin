import Foundation

// MARK: - File I/O Runtime (STDLIB-320/321/322/323)

final class RuntimeFileBox {
    let path: String
    init(_ path: String) { self.path = path }
}

final class RuntimeClassLoaderBox {}

private func runtimeFileBox(from raw: Int) -> RuntimeFileBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileBox.self)
}

private func resourceRootDirectory() -> URL {
    if let env = ProcessInfo.processInfo.environment["KSWIFTK_RESOURCE_ROOT"], !env.isEmpty {
        return URL(fileURLWithPath: env, isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

private func existingResourceURL(named name: String) -> URL? {
    guard !name.isEmpty else { return nil }
    let root = resourceRootDirectory().standardizedFileURL
    let resolved = root.appendingPathComponent(name).standardizedFileURL
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard resolved.path == root.path || resolved.path.hasPrefix(rootPath) else {
        return nil
    }
    return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
}

private func fileMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

// MARK: - STDLIB-320: File constructor and basic operations

@_cdecl("__kk_file_new")
public func __kk_file_new(_ pathRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pathRaw),
          let path = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_new received invalid path")
    }
    return registerRuntimeObject(RuntimeFileBox(path))
}

@_cdecl("__kk_file_new_parent_child")
public func __kk_file_new_parent_child(_ parentRaw: Int, _ childRaw: Int) -> Int {
    guard let parentPtr = UnsafeMutableRawPointer(bitPattern: parentRaw),
          let parent = extractString(from: parentPtr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_new_parent_child received invalid parent")
    }
    guard let childPtr = UnsafeMutableRawPointer(bitPattern: childRaw),
          let child = extractString(from: childPtr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_new_parent_child received invalid child")
    }
    let path = (parent as NSString).appendingPathComponent(child)
    return registerRuntimeObject(RuntimeFileBox(path))
}

@_cdecl("__kk_file_readText")
public func __kk_file_readText(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_readText received invalid File handle")
    }
    do {
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        return fileMakeStringRaw(content)
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
        return fileMakeStringRaw("")
    }
}

@_cdecl("__kk_classloader_getSystemClassLoader")
public func __kk_classloader_getSystemClassLoader() -> Int {
    registerRuntimeObject(RuntimeClassLoaderBox())
}

@_cdecl("__kk_classloader_getResource")
public func __kk_classloader_getResource(_ loaderRaw: Int, _ nameRaw: Int) -> Int {
    guard UnsafeMutableRawPointer(bitPattern: loaderRaw).flatMap({ tryCast($0, to: RuntimeClassLoaderBox.self) }) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_classloader_getResource received invalid ClassLoader handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr),
          let url = existingResourceURL(named: name)
    else {
        return runtimeNullSentinelInt
    }
    return fileMakeStringRaw(url.path)
}

@_cdecl("__kk_classloader_getResourceAsStream")
public func __kk_classloader_getResourceAsStream(_ loaderRaw: Int, _ nameRaw: Int) -> Int {
    guard UnsafeMutableRawPointer(bitPattern: loaderRaw).flatMap({ tryCast($0, to: RuntimeClassLoaderBox.self) }) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_classloader_getResourceAsStream received invalid ClassLoader handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr),
          let url = existingResourceURL(named: name),
          let data = try? Data(contentsOf: url)
    else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeInputStreamBox(data: data))
}

@_cdecl("__kk_resource_exists")
public func __kk_resource_exists(_ nameRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_resource_exists received invalid name")
    }
    return kk_box_bool(existingResourceURL(named: name) != nil ? 1 : 0)
}

@_cdecl("__kk_readResourceAsText")
public func __kk_readResourceAsText(_ nameRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_readResourceAsText received invalid name")
    }
    guard let url = existingResourceURL(named: name) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Resource not found: \(name)")
        return fileMakeStringRaw("")
    }
    do {
        return fileMakeStringRaw(try String(contentsOf: url, encoding: .utf8))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return fileMakeStringRaw("")
    }
}

// MARK: - STDLIB-321: File properties and existence checks

@_cdecl("__kk_file_path")
public func __kk_file_path(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_path received invalid File handle")
    }
    return fileMakeStringRaw(file.path)
}

// MARK: - STDLIB-567: File.bufferedReader()

private func runtimeBufferedReaderBox(from raw: Int) -> RuntimeBufferedReaderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedReaderBox.self)
}

private func runtimeInputStreamBox(from raw: Int) -> RuntimeInputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeInputStreamBox.self)
}

private func runtimeByteArrayBytes(from raw: Int) -> [UInt8]? {
    if let array = runtimeArrayBox(from: raw) {
        return array.elements.map { UInt8(truncatingIfNeeded: $0) }
    }
    if let list = runtimeListBox(from: raw) {
        return list.elements.map { UInt8(truncatingIfNeeded: $0) }
    }
    return nil
}

private func runtimeOutputStreamBox(from raw: Int) -> RuntimeOutputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeOutputStreamBox.self)
}

@_cdecl("__kk_buffered_reader_readLine")
public func __kk_buffered_reader_readLine(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_readLine received invalid BufferedReader handle")
    }
    guard let line = reader.readLine() else {
        return runtimeNullSentinelInt
    }
    return fileMakeStringRaw(line)
}

@_cdecl("__kk_buffered_reader_readLines")
public func __kk_buffered_reader_readLines(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_readLines received invalid BufferedReader handle")
    }
    let lines = reader.readLines()
    return registerRuntimeObject(RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) }))
}

@_cdecl("__kk_buffered_reader_close")
public func __kk_buffered_reader_close(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_close received invalid BufferedReader handle")
    }
    reader.close()
    return 0
}

@_cdecl("__kk_buffered_reader_read")
public func __kk_buffered_reader_read(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_read received invalid BufferedReader handle")
    }
    return reader.read()
}

@_cdecl("__kk_buffered_reader_ready")
public func __kk_buffered_reader_ready(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_ready received invalid BufferedReader handle")
    }
    return kk_box_bool(reader.ready() ? 1 : 0)
}

// MARK: - STDLIB-IO-FN-022: BufferedReader.iterator()
//
// Kotlin's `kotlin.io.BufferedReader.iterator()` operator extension returns an
// `Iterator<String>` that yields successive lines from the receiver. The
// underlying line buffering and termination semantics are inherited from
// `BufferedReader.readLine()`. Our implementation materialises all remaining
// lines eagerly into a list iterator so it can plug into the existing
// `RuntimeListIteratorBox` dispatch in `kk_iterator_hasNext` / `kk_iterator_next`.
// The observable behaviour (iteration order, blank line handling, EOF) matches
// `readLine()` because we delegate to it.
@_cdecl("__kk_buffered_reader_iterator")
public func __kk_buffered_reader_iterator(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_iterator received invalid BufferedReader handle")
    }
    let lineRaws = reader.readLines().map { fileMakeStringRaw($0) }
    return registerRuntimeObject(RuntimeListIteratorBox(elements: lineRaws))
}

// MARK: - STDLIB-IO-FN-040: Reader.useLines {}
//
// Kotlin's `kotlin.io.Reader.useLines(block)` extension reads all lines from the
// receiver Reader, passes them to `block` as a `Sequence<String>`, and closes
// the receiver before returning the block's result (Reader subclasses such as
// `BufferedReader` inherit this overload). Our implementation materialises the
// receiver's remaining lines into a `List<String>`, invokes the supplied lambda
// once via the collection HOF closure ABI, and closes the underlying buffered
// reader after the block runs —
// mirroring the JVM contract where the reader is closed even when the lambda
// returns or throws.
@_cdecl("__kk_buffered_reader_useLines")
public func __kk_buffered_reader_useLines(_ readerRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_useLines received invalid BufferedReader handle")
    }
    let lines = reader.readLines()
    let linesList = RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) })
    let linesListRaw = registerRuntimeObject(linesList)
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: linesListRaw, outThrown: &thrown)
    // Always close the reader to honour the `use { }` contract even on lambda throw.
    reader.close()
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

// MARK: - STDLIB-IO-FN-017: Reader.forEachLine { line -> Unit }
//
// Kotlin's `kotlin.io.Reader.forEachLine(action)` extension reads lines from the
// receiver one by one and invokes `action` with each line as a `String`. Iteration
// stops early when the action throws (the thrown value is propagated via `outThrown`).
// Unlike `useLines`, the reader is NOT automatically closed after iteration ends —
// this mirrors the JVM contract where `forEachLine` leaves the reader open.
@_cdecl("__kk_buffered_reader_forEachLine")
public func __kk_buffered_reader_forEachLine(
    _ readerRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError(
            "KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_forEachLine received invalid BufferedReader handle"
        )
    }
    for line in reader.readLines() {
        let lineRaw = fileMakeStringRaw(line)
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: lineRaw, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return 0
}

// MARK: - STDLIB-IO-FN-033: Reader.readText()
//
// Kotlin's `kotlin.io.Reader.readText(): String` extension drains the remaining
// content of a `Reader` and returns it as a single `String`. In KSwiftK every
// concrete `Reader` instance is currently a `BufferedReader` so we dispatch to
// `RuntimeBufferedReaderBox.readText()`. The function does NOT close the
// reader, matching the stdlib contract (callers should pair with `use { }`).
// Errors during stream reads bubble up as an empty string with no thrown
// exception, mirroring the lenient behaviour of our other reader helpers
// (`readLine`, `readLines`). The Sema extension signature is `() -> String`,
// so the only ABI argument is the receiver handle — no `outThrown` parameter.
@_cdecl("__kk_reader_readText")
public func __kk_reader_readText(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_readText received invalid Reader handle")
    }
    return fileMakeStringRaw(reader.readText())
}

// MARK: - STDLIB-IO-FN-007: InputStream.bufferedReader(charset)
//
// Kotlin's `InputStream.bufferedReader(charset: Charset = Charsets.UTF_8): BufferedReader`
// is a top-level extension in `kotlin.io`. Charset selection is delegated to
// the `BufferedReader` returned here — the runtime currently decodes lines as
// UTF-8, matching the rest of the `BufferedReader` API (see
// `RuntimeBufferedReaderBox.readLine`). The `charsetRaw` argument is accepted
// for ABI compatibility with future charset support and is otherwise ignored.
@_cdecl("__kk_input_stream_bufferedReader")
public func __kk_input_stream_bufferedReader(
    _ streamRaw: Int,
    _ charsetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = charsetRaw
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_bufferedReader received invalid InputStream handle")
    }
    let remaining = stream.drainRemaining()
    return registerRuntimeObject(RuntimeBufferedReaderBox(data: remaining))
}

// MARK: - STDLIB-IO-091: BufferedWriter

private func runtimeBufferedWriterBox(from raw: Int) -> RuntimeBufferedWriterBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedWriterBox.self)
}

@_cdecl("__kk_buffered_writer_write")
public func __kk_buffered_writer_write(_ writerRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_write received invalid BufferedWriter handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_write received invalid text")
    }
    do {
        try writer.write(text)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_buffered_writer_new_line")
public func __kk_buffered_writer_new_line(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_new_line received invalid BufferedWriter handle")
    }
    do {
        try writer.newLine()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_buffered_writer_flush")
public func __kk_buffered_writer_flush(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_flush received invalid BufferedWriter handle")
    }
    do {
        try writer.flush()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_buffered_writer_close")
public func __kk_buffered_writer_close(_ writerRaw: Int) -> Int {
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_close received invalid BufferedWriter handle")
    }
    writer.close()
    return 0
}

// MARK: - STDLIB-IO-FN-006: Writer.buffered(bufferSize)

@_cdecl("__kk_writer_buffered_default")
public func __kk_writer_buffered_default(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    __kk_writer_buffered(writerRaw, 8192, outThrown)
}

@_cdecl("__kk_writer_buffered")
public func __kk_writer_buffered(_ writerRaw: Int, _ bufferSizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard bufferSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "bufferSize must be positive")
        return 0
    }
    guard runtimeBufferedWriterBox(from: writerRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_writer_buffered received invalid Writer handle")
    }
    return writerRaw
}

@_cdecl("__kk_bytearrayinputstream_new")
public func __kk_bytearrayinputstream_new(_ bufferRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArrayBytes(from: bufferRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> buffer")
        return 0
    }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

// STDLIB-IO-FN-020: ByteArray.inputStream() — wraps the entire byte array as a
// ByteArrayInputStream. Mirrors the Kotlin stdlib `public fun ByteArray.inputStream()`.
@_cdecl("__kk_bytearray_inputStream")
public func __kk_bytearray_inputStream(_ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArrayBytes(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray handle")
        return 0
    }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

// STDLIB-IO-FN-021: ByteArray.inputStream(offset: Int, length: Int) — wraps a
// subrange of the byte array as a ByteArrayInputStream. Mirrors the Kotlin stdlib
// `public fun ByteArray.inputStream(offset: Int, length: Int)`.
@_cdecl("__kk_bytearray_inputStream_range")
public func __kk_bytearray_inputStream_range(
    _ arrayRaw: Int,
    _ offsetRaw: Int,
    _ lengthRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArrayBytes(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray handle")
        return 0
    }
    let offset = offsetRaw
    let length = lengthRaw
    guard offset >= 0, length >= 0, offset + length <= bytes.count else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "offset=\(offset) length=\(length) size=\(bytes.count)"
        )
        return 0
    }
    let slice = Array(bytes[offset ..< offset + length])
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(slice)))
}

// STDLIB-IO-FN-011: String.byteInputStream() — encodes the receiver as UTF-8 and
// returns a ByteArrayInputStream over the resulting bytes. Default charset overload
// mirrors `String.toByteArray()` semantics for behavioral consistency.
@_cdecl("__kk_string_byteInputStream_flat")
public func __kk_string_byteInputStream_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeStringByteInputStream(source)
}

// STDLIB-IO-FN-011: String.byteInputStream(charset: Charset) — charset-aware
// overload. Reuses the same charset table as String.toByteArray(charset).
@_cdecl("__kk_string_byteInputStream_charset_flat")
public func __kk_string_byteInputStream_charset_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ charsetTag: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeStringByteInputStream(source, charsetTag: charsetTag)
}

private func runtimeStringByteInputStream(_ source: String) -> Int {
    let bytes = source.utf8.map { UInt8($0) }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

private func runtimeStringByteInputStream(_ source: String, charsetTag: Int) -> Int {
    let bytesRaw = runtimeStringToByteArrayWithCharsetRaw(source, charsetTag: charsetTag)
    guard let bytes = runtimeByteArrayBytes(from: bytesRaw) else {
        // Fall back to UTF-8 if the encoded bytes cannot be retrieved (should not happen)
        return runtimeStringByteInputStream(source)
    }
    let unsignedBytes = bytes.map { UInt8(truncatingIfNeeded: $0) }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(unsignedBytes)))
}

@_cdecl("__kk_input_stream_read")
public func __kk_input_stream_read(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_read received invalid InputStream handle")
    }
    return stream.readByte()
}

@_cdecl("__kk_input_stream_available")
public func __kk_input_stream_available(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_available received invalid InputStream handle")
    }
    return stream.available()
}

@_cdecl("__kk_input_stream_skip")
public func __kk_input_stream_skip(_ streamRaw: Int, _ countRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_skip received invalid InputStream handle")
    }
    return stream.skip(countRaw)
}

@_cdecl("__kk_input_stream_read_bytes")
public func __kk_input_stream_read_bytes(_ streamRaw: Int, _ bytesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_read_bytes received invalid InputStream handle")
    }
    guard let list = runtimeListBox(from: bytesRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> buffer")
        return -1
    }
    return stream.read(into: list)
}

// MARK: - InputStream.readBytes() (STDLIB-IO-FN-029)
//
// Kotlin defines:
//   public fun InputStream.readBytes(): ByteArray
//
// The extension reads all remaining bytes from `this` into a freshly allocated
// ByteArray. We model `ByteArray` as a `List<Int>` whose elements are signed
// Int values in [-128, 127], matching the rest of the runtime's ByteArray
// representation.
//
// The implementation drains the underlying `RuntimeInputStreamBox` in a single
// pass (or, for `SequenceInputStream`, walks both chained streams to EOF).
// The receiver is not closed — `InputStream.readBytes()` mirrors JVM
// `InputStream.readAllBytes()` in that the caller is responsible for closing
// the stream (typically via `.use { it.readBytes() }`).
@_cdecl("__kk_input_stream_readAllBytes")
public func __kk_input_stream_readAllBytes(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    // Try a plain InputStream first.
    if let stream = runtimeInputStreamBox(from: streamRaw) {
        let bytes = stream.readAllBytes()
        return registerRuntimeObject(RuntimeListBox(elements: bytes))
    }
    // Fall back to a SequenceInputStream chain.
    if let ptr = UnsafeMutableRawPointer(bitPattern: streamRaw),
       let sequenceStream = tryCast(ptr, to: RuntimeSequenceInputStreamBox.self)
    {
        let bytes = sequenceStream.readAllBytes()
        return registerRuntimeObject(RuntimeListBox(elements: bytes))
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_readAllBytes received invalid InputStream handle")
}

@_cdecl("__kk_input_stream_mark")
public func __kk_input_stream_mark(_ streamRaw: Int, _ readLimitRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_mark received invalid InputStream handle")
    }
    stream.mark(readLimit: readLimitRaw)
    return 0
}

@_cdecl("__kk_input_stream_reset")
public func __kk_input_stream_reset(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_reset received invalid InputStream handle")
    }
    if !stream.reset() {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: mark/reset not supported")
    }
    return 0
}

@_cdecl("__kk_input_stream_mark_supported")
public func __kk_input_stream_mark_supported(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_mark_supported received invalid InputStream handle")
    }
    return kk_box_bool(stream.markSupported() ? 1 : 0)
}

@_cdecl("__kk_input_stream_close")
public func __kk_input_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_close received invalid InputStream handle")
    }
    stream.close()
    return 0
}

// MARK: - STDLIB-IO-FN-013: InputStream.copyTo(out, bufferSize)
//
// Kotlin signature:
//   public fun InputStream.copyTo(
//       out: OutputStream,
//       bufferSize: Int = DEFAULT_BUFFER_SIZE
//   ): Long
//
// Copies bytes from this InputStream into the given OutputStream until
// all available bytes have been read, returning the total byte count as a
// boxed Long.  The InputStream is not closed after copying (matching
// Kotlin/JVM behaviour).
@_cdecl("__kk_input_stream_copyTo")
public func __kk_input_stream_copyTo(
    _ streamRaw: Int,
    _ outStreamRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let inputStream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_copyTo received invalid InputStream handle")
    }
    guard let outputStream = runtimeOutputStreamBox(from: outStreamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_copyTo received invalid OutputStream handle")
    }
    let bufferSize = max(1, kk_unbox_int(bufferSizeRaw))
    var totalBytesCopied: Int = 0
    let buffer = RuntimeListBox(elements: Array(repeating: 0, count: bufferSize))
    while true {
        let bytesRead = inputStream.read(into: buffer)
        if bytesRead <= 0 { break }
        let chunk = Array(buffer.elements.prefix(bytesRead))
        do {
            try outputStream.writeBytes(chunk)
        } catch {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: \(error.localizedDescription)"
            )
            return kk_box_long(totalBytesCopied)
        }
        totalBytesCopied += bytesRead
    }
    return kk_box_long(totalBytesCopied)
}

// MARK: - InputStream.buffered (STDLIB-IO-FN-003)
//
// Kotlin's `InputStream.buffered(bufferSize)` extension returns a
// BufferedInputStream wrapping the underlying stream.  Since the byte-level
// reading methods provided by RuntimeInputStreamBox already operate against
// an in-memory Data buffer, returning the same handle re-typed as a
// BufferedInputStream preserves observable Kotlin semantics:
//   - read()/available()/skip()/close() continue to delegate to the same
//     underlying byte source
//   - mark/reset remain unsupported (mirroring FileInputStream behaviour)
//   - the buffer size argument is honoured by the type but does not alter
//     the in-memory byte sequence
//
// If a future revision introduces a dedicated BufferedInputStreamBox with
// look-ahead semantics, this function will continue to be the single seam
// for materialising one from an arbitrary InputStream handle.
@_cdecl("__kk_input_stream_buffered_default")
public func __kk_input_stream_buffered_default(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeInputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_buffered_default received invalid InputStream handle")
    }
    // The underlying RuntimeInputStreamBox already buffers via Data, so we
    // can hand out the same handle re-typed.  Returning the same raw value
    // keeps reference counting consistent.
    return streamRaw
}

@_cdecl("__kk_input_stream_buffered")
public func __kk_input_stream_buffered(_ streamRaw: Int, _ bufferSizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeInputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_buffered received invalid InputStream handle")
    }
    // Kotlin's reference implementation throws IllegalArgumentException for
    // non-positive buffer sizes (BufferedInputStream's underlying JVM type
    // does the same).  Surface that diagnostic via the standard outThrown
    // channel rather than returning a sentinel.
    if bufferSizeRaw <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Buffer size <= 0")
        return 0
    }
    return streamRaw
}

// MARK: - SequenceInputStream (STDLIB-IO-092)

private func runtimeSequenceInputStreamBox(from raw: Int) -> RuntimeSequenceInputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeSequenceInputStreamBox.self)
}

@_cdecl("__kk_sequence_input_stream_new")
public func __kk_sequence_input_stream_new(_ firstRaw: Int, _ secondRaw: Int) -> Int {
    guard let first = runtimeInputStreamBox(from: firstRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_new: invalid first InputStream handle")
    }
    guard let second = runtimeInputStreamBox(from: secondRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_new: invalid second InputStream handle")
    }
    return registerRuntimeObject(RuntimeSequenceInputStreamBox(first: first, second: second))
}

@_cdecl("__kk_sequence_input_stream_read")
public func __kk_sequence_input_stream_read(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_read received invalid SequenceInputStream handle")
    }
    return stream.readByte()
}

@_cdecl("__kk_sequence_input_stream_available")
public func __kk_sequence_input_stream_available(_ streamRaw: Int) -> Int {
    guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_available received invalid SequenceInputStream handle")
    }
    return stream.available()
}

@_cdecl("__kk_sequence_input_stream_close")
public func __kk_sequence_input_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_close received invalid SequenceInputStream handle")
    }
    stream.close()
    return 0
}

@_cdecl("__kk_output_stream_write_byte")
public func __kk_output_stream_write_byte(_ streamRaw: Int, _ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_write_byte received invalid OutputStream handle")
    }
    do {
        try stream.writeByte(valueRaw)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_output_stream_write_bytes")
public func __kk_output_stream_write_bytes(_ streamRaw: Int, _ bytesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_write_bytes received invalid OutputStream handle")
    }
    guard let list = runtimeListBox(from: bytesRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> buffer")
        return 0
    }
    do {
        try stream.writeBytes(list.elements)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_output_stream_flush")
public func __kk_output_stream_flush(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_flush received invalid OutputStream handle")
    }
    do {
        try stream.flush()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_output_stream_close")
public func __kk_output_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_close received invalid OutputStream handle")
    }
    stream.close()
    return 0
}

// MARK: - STDLIB-IO-FN-009: OutputStream.bufferedWriter(charset)

/// Maps Kotlin `Charset` tag (mirrors `kotlin.text.Charsets.*` IDs in the
/// runtime ABI) to a Swift `String.Encoding`.  Mirrors the helper in
/// `RuntimePath.swift` so this file stays self-contained.
private func outputStreamEncoding(for charsetRaw: Int) -> String.Encoding {
    switch charsetRaw {
    case 1: .isoLatin1
    case 2: .ascii
    case 3: .utf16
    case 4: .utf16BigEndian
    case 5: .utf16LittleEndian
    case 6: .utf32
    case 7: .utf32BigEndian
    case 8: .utf32LittleEndian
    default: .utf8
    }
}

/// `kotlin.io.bufferedWriter(charset: Charset = Charsets.UTF_8): BufferedWriter`
/// extension on `java.io.OutputStream`.
///
/// JVM semantics: returns a new `BufferedWriter` wrapping an `OutputStreamWriter`
/// over this output stream using the specified charset.  Subsequent writes/closes
/// of the returned writer affect the underlying stream; the original `OutputStream`
/// handle should no longer be used directly.
@_cdecl("__kk_output_stream_bufferedWriter")
public func __kk_output_stream_bufferedWriter(_ streamRaw: Int, _ charsetRaw: Int) -> Int {
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_bufferedWriter received invalid OutputStream handle")
    }
    let encoding = outputStreamEncoding(for: charsetRaw)
    guard let writer = stream.makeBufferedWriter(encoding: encoding) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_bufferedWriter cannot wrap non-file-handle OutputStream")
    }
    return registerRuntimeObject(writer)
}

// MARK: - STDLIB-IO-FN-004: OutputStream.buffered() / buffered(bufferSize)

/// Returns an OutputStream that wraps the receiver with buffering. Because the
/// underlying `RuntimeOutputStreamBox` is already streamed through the OS-level
/// FileHandle (which performs its own buffering), the wrapped handle is the
/// receiver itself — matching Kotlin's identity contract for an already-buffered
/// stream (`if (this is BufferedOutputStream) this else BufferedOutputStream(this)`).
@_cdecl("__kk_output_stream_buffered")
public func __kk_output_stream_buffered(_ streamRaw: Int) -> Int {
    guard runtimeOutputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_buffered received invalid OutputStream handle")
    }
    return streamRaw
}

/// Sized overload of `buffered()`. The `bufferSize` parameter is currently
/// honored by the underlying OS-level FileHandle, so this overload also returns
/// the receiver handle. Reserved for a future BufferedOutputStream-backed
/// implementation that respects the requested buffer size explicitly.
@_cdecl("__kk_output_stream_buffered_sized")
public func __kk_output_stream_buffered_sized(_ streamRaw: Int, _ bufferSize: Int) -> Int {
    _ = bufferSize // Reserved for explicit BufferedOutputStream implementation.
    guard runtimeOutputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_buffered_sized received invalid OutputStream handle")
    }
    return streamRaw
}

// MARK: - STDLIB-IO-FN-014: Reader.copyTo(out: Writer, bufferSize) -> Long

/// Kotlin's default buffer size for `kotlin.io.copyTo`.  Matches
/// `kotlin.io.DEFAULT_BUFFER_SIZE` (16 KiB).
private let kReaderCopyToDefaultBufferSize: Int = 16 * 1024

/// `kotlin.io.Reader.copyTo(out: Writer, bufferSize: Int = DEFAULT_BUFFER_SIZE): Long`
///
/// Copies every character that remains in the receiver into `out` using an
/// internal buffer of `bufferSize` characters and returns the total number of
/// characters transferred.  Mirrors the JVM contract:
///   - Neither the receiver nor `out` is closed by this function.
///   - The receiver is read until EOF (`Reader.read()` returning `-1`).
///   - Characters are emitted to `out` as `String` chunks of up to
///     `bufferSize` characters at a time.
///   - A non-positive `bufferSize` raises `IllegalArgumentException` to match
///     the behaviour of `kotlin.io.copyTo` on the JVM.
///
/// Concrete `Reader` / `Writer` boxes currently supported by the runtime are
/// `RuntimeBufferedReaderBox` and `RuntimeBufferedWriterBox` — the only
/// character-stream types modelled in the synthetic stubs.  Passing any other
/// box panics with a clear diagnostic so test failures surface immediately.
@_cdecl("__kk_reader_copyTo")
public func __kk_reader_copyTo(
    _ readerRaw: Int,
    _ writerRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0

    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_copyTo received invalid Reader handle")
    }
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_copyTo received invalid Writer handle")
    }

    if bufferSizeRaw <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "bufferSize must be positive (was \(bufferSizeRaw))"
        )
        return kk_box_long(0)
    }

    var copied: Int = 0
    var pending = String.UnicodeScalarView()
    pending.reserveCapacity(bufferSizeRaw)

    while true {
        let charCode = reader.read()
        if charCode < 0 {
            break // EOF
        }
        guard let scalar = Unicode.Scalar(UInt32(charCode)) else {
            // Invalid scalar — surface as IOException to match JVM-style
            // surface for malformed character data.
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: invalid Unicode scalar in Reader stream (code point \(charCode))"
            )
            return kk_box_long(copied)
        }
        pending.append(scalar)
        copied += 1

        if pending.count >= bufferSizeRaw {
            do {
                try writer.write(String(pending))
            } catch {
                outThrown?.pointee = runtimeAllocateThrowable(
                    message: "IOException: \(error.localizedDescription)"
                )
                return kk_box_long(copied)
            }
            pending.removeAll(keepingCapacity: true)
        }
    }

    if !pending.isEmpty {
        do {
            try writer.write(String(pending))
        } catch {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: \(error.localizedDescription)"
            )
            return kk_box_long(copied)
        }
    }

    return kk_box_long(copied)
}

/// Zero-bufferSize overload — `Reader.copyTo(out)` defaults to
/// `DEFAULT_BUFFER_SIZE`.  STDLIB-IO-FN-014.
@_cdecl("__kk_reader_copyTo_default")
public func __kk_reader_copyTo_default(
    _ readerRaw: Int,
    _ writerRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_reader_copyTo(readerRaw, writerRaw, kReaderCopyToDefaultBufferSize, outThrown)
}

// Shared runtime storage for java.nio.file.attribute.FileTime.
//
// Path APIs also expose this value, so this support is kept independently of
// the removed java.nio.file.Files utility bridge.
final class RuntimeFileTimeBox {
    let milliseconds: Int

    init(milliseconds: Int) {
        self.milliseconds = milliseconds
    }
}

private func runtimeFileTimeBox(from raw: Int) -> RuntimeFileTimeBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileTimeBox.self)
}

/// FileTime.toMillis() — returns the stored epoch millis.
@_cdecl("__kk_fileTime_toMillis")
public func __kk_fileTime_toMillis(_ fileTimeRaw: Int) -> Int {
    guard let fileTime = runtimeFileTimeBox(from: fileTimeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_fileTime_toMillis received invalid FileTime handle")
    }
    return fileTime.milliseconds
}
