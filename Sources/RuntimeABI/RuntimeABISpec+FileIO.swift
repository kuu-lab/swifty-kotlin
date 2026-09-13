/// `RuntimeABISpec.fileIOFunctions` (STDLIB-320/321/322/323) extracted from
/// `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    // MARK: - File I/O (STDLIB-320/321/322/323)

    static let fileIOFunctions: [RuntimeABIFunctionSpec] = [
        // File must stay constructible for kotlin.io.FileSystemException (KSP-619)
        // and Files.kt's resolveSibling/normalize (KSP-483); see CLEANUP-STUB-107.
        RuntimeABIFunctionSpec(
            name: "__kk_file_new",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        // STDLIB-IO-087: File(parent, child) constructor
        RuntimeABIFunctionSpec(
            name: "__kk_file_new_parent_child",
            parameters: [
                RuntimeABIParameter(name: "parentRaw", type: .intptr),
                RuntimeABIParameter(name: "childRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_file_readText",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_file_path",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        // STDLIB-567: File.bufferedReader()
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_reader_readLine",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_reader_readLines",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_reader_close",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        // STDLIB-IO-091: BufferedReader.read() / ready()
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_reader_read",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_reader_ready",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        // STDLIB-IO-FN-022: BufferedReader.iterator() -> Iterator<String>
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_reader_iterator",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        // STDLIB-IO-FN-040: Reader.useLines { lines -> T }
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_reader_useLines",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-017: Reader.forEachLine { line -> Unit }
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_reader_forEachLine",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-033: Reader.readText() -> String
        RuntimeABIFunctionSpec(
            name: "__kk_reader_readText",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-091/093: BufferedWriter
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_writer_write",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "textRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_writer_new_line",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_writer_flush",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_buffered_writer_close",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-006: Writer.buffered
        RuntimeABIFunctionSpec(
            name: "__kk_writer_buffered_default",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_writer_buffered",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "bufferSizeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_bytearrayinputstream_new",
            parameters: [
                RuntimeABIParameter(name: "bufferRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-020: ByteArray.inputStream()
        RuntimeABIFunctionSpec(
            name: "__kk_bytearray_inputStream",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-021: ByteArray.inputStream(offset: Int, length: Int)
        RuntimeABIFunctionSpec(
            name: "__kk_bytearray_inputStream_range",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "offsetRaw", type: .intptr),
                RuntimeABIParameter(name: "lengthRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-011: String.byteInputStream()
        RuntimeABIFunctionSpec(
            name: "__kk_string_byteInputStream_flat",
            parameters: [
                RuntimeABIParameter(name: "receiverData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "receiverLength", type: .intptr),
                RuntimeABIParameter(name: "receiverByteCount", type: .intptr),
                RuntimeABIParameter(name: "receiverHash", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        // STDLIB-IO-FN-011: String.byteInputStream(charset: Charset)
        RuntimeABIFunctionSpec(
            name: "__kk_string_byteInputStream_charset_flat",
            parameters: [
                RuntimeABIParameter(name: "receiverData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "receiverLength", type: .intptr),
                RuntimeABIParameter(name: "receiverByteCount", type: .intptr),
                RuntimeABIParameter(name: "receiverHash", type: .intptr),
                RuntimeABIParameter(name: "charsetTag", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_read",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_available",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_skip",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "countRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_read_bytes",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-029: InputStream.readBytes() -> ByteArray (drains the stream)
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_readAllBytes",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_close",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-003: InputStream.buffered(bufferSize) returning BufferedInputStream
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_buffered_default",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_buffered",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "bufferSizeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-013: InputStream.copyTo(out, bufferSize) -> Long
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_copyTo",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outStreamRaw", type: .intptr),
                RuntimeABIParameter(name: "bufferSizeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-007: kotlin.io.InputStream.bufferedReader(charset)
        RuntimeABIFunctionSpec(
            name: "__kk_input_stream_bufferedReader",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_output_stream_write_byte",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_output_stream_write_bytes",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_output_stream_flush",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_output_stream_close",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-009: OutputStream.bufferedWriter(charset)
        RuntimeABIFunctionSpec(
            name: "__kk_output_stream_bufferedWriter",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-004: OutputStream.buffered() / buffered(bufferSize)
        RuntimeABIFunctionSpec(
            name: "__kk_output_stream_buffered",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-014: Reader.copyTo(out: Writer, bufferSize: Int) -> Long
        RuntimeABIFunctionSpec(
            name: "__kk_reader_copyTo",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "bufferSizeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_reader_copyTo_default",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_output_stream_buffered_sized",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "bufferSize", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_classloader_getSystemClassLoader",
            parameters: [],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_classloader_getResource",
            parameters: [
                RuntimeABIParameter(name: "loaderRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_classloader_getResourceAsStream",
            parameters: [
                RuntimeABIParameter(name: "loaderRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_resource_exists",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_readResourceAsText",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
    ]

}
