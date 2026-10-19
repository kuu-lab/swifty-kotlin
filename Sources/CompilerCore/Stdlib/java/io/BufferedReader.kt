package java.io

import kotlin.internal.KsSymbolName

public open class BufferedReader : Reader {
    @KsSymbolName("__kk_buffered_reader_new")
    public constructor(input: Reader)

    @KsSymbolName("__kk_buffered_reader_close")
    public external override fun close(): Unit
}
