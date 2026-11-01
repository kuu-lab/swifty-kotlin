private let abi = RuntimeABISectionBuilder("FileIO")

public extension RuntimeABISpec {
    static let fileIOFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_input_stream_reader_new", "streamRaw"),
        abi.nt("__kk_buffered_reader_new", "readerRaw"),
        // KUU-3077 reason code: memory representation. StringWriter shares its
        // mutable buffer with BufferedWriter through runtime-owned boxes.
        abi.nt("__kk_string_writer_new_default"),
        abi.th("__kk_string_writer_new", "initialSize outThrown"),
        abi.nt("__kk_string_writer_to_string", "writerRaw"),
        abi.nt("__kk_string_writer_get_buffer", "writerRaw"),
        // File must stay constructible for kotlin.io.FileSystemException (KSP-619)
        // and Files.kt's resolveSibling/normalize (KSP-483); see CLEANUP-STUB-107.
        abi.th("__kk_bytearray_output_stream_new_default"),
        abi.th("__kk_bytearray_output_stream_new", "value0 outThrown"),
        abi.th("__kk_bytearray_output_stream_to_byte_array", "value0"),
        abi.th("__kk_bytearray_output_stream_reset", "value0"),
        abi.th("__kk_bytearray_output_stream_size", "value0"),
        abi.th("__kk_bytearray_output_stream_to_string", "value0"),
        abi.nt("__kk_file_new", "pathRaw"),
        abi.nt("__kk_file_new_parent_child", "parentRaw childRaw"),
        abi.th("__kk_file_readText", "fileRaw charsetTag outThrown"),
        abi.nt("__kk_file_path", "fileRaw"),
        abi.nt("__kk_buffered_reader_readLine", "readerRaw"),
        abi.nt("__kk_buffered_reader_readLines", "readerRaw"),
        abi.nt("__kk_buffered_reader_close", "readerRaw"),
        abi.nt("__kk_buffered_reader_read", "readerRaw"),
        abi.nt("__kk_buffered_reader_ready", "readerRaw"),
        abi.nt("__kk_buffered_reader_iterator", "readerRaw"),
        abi.th("__kk_buffered_reader_useLines", "readerRaw fnPtr closureRaw outThrown"),
        abi.th("__kk_buffered_reader_forEachLine", "readerRaw fnPtr closureRaw outThrown"),
        abi.th("__kk_reader_readText", "readerRaw"),
        abi.th("__kk_buffered_writer_write", "writerRaw textRaw outThrown"),
        abi.th("__kk_buffered_writer_new_line", "writerRaw outThrown"),
        abi.th("__kk_buffered_writer_flush", "writerRaw outThrown"),
        abi.th("__kk_buffered_writer_close_throwing", "writerRaw outThrown"),
        abi.th("__kk_writer_buffered_default", "writerRaw outThrown"),
        abi.th("__kk_writer_buffered", "writerRaw bufferSizeRaw outThrown"),
        abi.th("__kk_bytearrayinputstream_new", "bufferRaw outThrown"),
        abi.th("__kk_bytearray_inputStream", "arrayRaw outThrown"),
        abi.th("__kk_bytearray_inputStream_range", "arrayRaw offsetRaw lengthRaw outThrown"),
        abi.nt("__kk_string_byteInputStream_flat", "receiverData:nullableConstUInt8Pointer receiverLength receiverByteCount receiverHash"),
        abi.nt("__kk_string_byteInputStream_charset_flat", "receiverData:nullableConstUInt8Pointer receiverLength receiverByteCount receiverHash charsetTag"),
        abi.th("__kk_input_stream_read", "streamRaw outThrown"),
        abi.th("__kk_input_stream_available", "streamRaw"),
        abi.th("__kk_input_stream_skip", "streamRaw countRaw outThrown"),
        abi.th("__kk_input_stream_read_bytes", "streamRaw bytesRaw outThrown"),
        abi.th("__kk_input_stream_readAllBytes", "streamRaw outThrown"),
        abi.th("__kk_input_stream_close", "streamRaw"),
        abi.th("__kk_input_stream_buffered_default", "streamRaw outThrown"),
        abi.th("__kk_input_stream_buffered", "streamRaw bufferSizeRaw outThrown"),
        abi.th("__kk_input_stream_copyTo", "streamRaw outStreamRaw bufferSizeRaw outThrown"),
        abi.th("__kk_input_stream_bufferedReader", "streamRaw charsetRaw outThrown"),
        abi.th("__kk_output_stream_write_byte", "streamRaw valueRaw outThrown"),
        abi.th("__kk_output_stream_write_bytes", "streamRaw bytesRaw outThrown"),
        abi.th("__kk_output_stream_flush", "streamRaw outThrown"),
        abi.th("__kk_output_stream_bufferedWriter", "streamRaw charsetRaw"),
        abi.th("__kk_output_stream_buffered", "streamRaw"),
        abi.th("__kk_reader_copyTo", "readerRaw writerRaw bufferSizeRaw outThrown"),
        abi.th("__kk_reader_copyTo_default", "readerRaw writerRaw outThrown"),
        // `java.io.Reader.read(CharArray, Int, Int)` — the class's virtual
        // char-source contract (KUU-4031); reader boxes install it as vtable
        // slot `readerReadChars`, Kotlin subclasses land their override in
        // the same slot.
        abi.th("__kk_reader_read_range", "readerRaw bufferRaw offsetRaw lengthRaw outThrown"),
        abi.th("__kk_output_stream_buffered_sized", "streamRaw bufferSize"),
        abi.th("__kk_io_stream_to_string", "stream outThrown"),
        abi.th("__kk_sequence_input_stream_available_throwing", "stream outThrown"),
        abi.th("__kk_sequence_input_stream_close_throwing", "stream outThrown"),
        // KUU1762: foreign stream range/closure storage and error channels only.
        abi.nt("__kk_kotlin_source_input_stream", "readFn readClosure rangeFn rangeClosure availableFn availableClosure closeFn closeClosure descriptionFn descriptionClosure"),
        abi.nt("__kk_kotlin_sink_output_stream_range", "writeFn writeClosure flushFn flushClosure closeFn closeClosure descriptionFn descriptionClosure"),
        abi.th("__kk_input_stream_read_range", "streamRaw bytesRaw offset count outThrown"),
        abi.th("__kk_output_stream_write_range", "streamRaw bytesRaw offset count outThrown"),
        abi.th("__kk_input_stream_available_throwing", "streamRaw outThrown"),
        abi.th("__kk_input_stream_close_throwing", "streamRaw outThrown"),
        abi.th("__kk_output_stream_close_throwing", "streamRaw outThrown"),
        // KSP-1553: kotlinx.io Sink.asOutputStream() — the write/flush/close
        // Kotlin lambdas arrive as (fnPtr, closureRaw) pairs expanded by
        // KIRLowering, same convention as `__kk_synchronized` /
        // `kk_worker_execute`.
        abi.nt("__kk_kotlin_sink_output_stream", "writeFnPtr writeClosureRaw flushFnPtr flushClosureRaw closeFnPtr closeClosureRaw"),
        abi.th("__kk_native_filechannel_open", "pathRaw options outThrown"),
        abi.th("__kk_native_filechannel_write", "descriptor bytesRaw offset count outThrown"),
        abi.th("__kk_native_nio_create_file", "pathRaw outThrown"),
        abi.nt("__kk_classloader_getSystemClassLoader"),
        abi.nt("__kk_classloader_getResource", "loaderRaw nameRaw"),
        abi.nt("__kk_classloader_getResourceAsStream", "loaderRaw nameRaw"),
        abi.nt("__kk_resource_exists", "nameRaw"),
        abi.th("__kk_readResourceAsText", "nameRaw outThrown"),
    ]

}
