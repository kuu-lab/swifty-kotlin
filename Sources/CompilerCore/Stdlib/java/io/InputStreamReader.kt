package java.io

import kotlin.internal.KsSymbolName

/** Decodes a byte stream using the native default charset (UTF-8). */
public open class InputStreamReader : Reader {
    @KsSymbolName("__kk_input_stream_reader_new")
    public constructor(input: InputStream)

    @KsSymbolName("__kk_buffered_reader_read")
    public external fun read(): Int

    @KsSymbolName("__kk_reader_read_range")
    public external override fun read(buffer: CharArray, offset: Int, length: Int): Int

    @KsSymbolName("__kk_buffered_reader_ready")
    public external fun ready(): Boolean

    @KsSymbolName("__kk_buffered_reader_close")
    public external override fun close(): Unit
}
