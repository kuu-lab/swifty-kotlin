package java.io

import kotlin.internal.KsSymbolName

public open class BufferedWriter : Writer {
    @KsSymbolName("__kk_writer_buffered_default")
    public constructor(out: Writer)

    @KsSymbolName("__kk_writer_buffered")
    public constructor(out: Writer, size: Int)
}
