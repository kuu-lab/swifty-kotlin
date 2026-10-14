package java.io

import kotlin.internal.KsSymbolName

/** Wraps an existing character reader without consuming it at construction. */
public open class BufferedReader : Reader {
    @KsSymbolName("__kk_buffered_reader_new")
    public constructor(input: Reader)

    @KsSymbolName("__kk_buffered_reader_close")
    public external override fun close(): Unit
}
