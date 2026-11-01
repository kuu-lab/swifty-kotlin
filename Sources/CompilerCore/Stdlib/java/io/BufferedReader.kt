package java.io

import kotlin.internal.KsSymbolName

public open class BufferedReader : Reader {
    @KsSymbolName("__kk_buffered_reader_new")
    public constructor(input: Reader)

    @KsSymbolName("__kk_reader_read_range")
    public external override fun read(buffer: CharArray, offset: Int, length: Int): Int

    @KsSymbolName("__kk_buffered_reader_close")
    public external override fun close(): Unit
}
