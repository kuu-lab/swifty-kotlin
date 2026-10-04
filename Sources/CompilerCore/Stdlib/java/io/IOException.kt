package java.io

import kotlin.Exception
import kotlin.internal.KsSymbolName

/**
 * Signals that an I/O exception of some sort has occurred.
 *
 * The runtime-backed constructors preserve the JVM-visible `java.io.IOException`
 * nominal type so stream failures can be caught as either `IOException` or
 * `Exception`.
 */
public open class IOException : Exception {
    @KsSymbolName("__kk_io_exception_new")
    public constructor()

    @KsSymbolName("__kk_io_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_io_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_io_exception_new_cause")
    public constructor(cause: Throwable?)
}
