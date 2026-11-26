package kotlin.text

import java.nio.charset.Charset
import kotlin.jvm.JvmField
import kotlin.jvm.JvmName

object Charsets {
    @JvmField val UTF_8: Charset = Charset.forName("UTF-8")
    @JvmField val UTF_16: Charset = Charset.forName("UTF-16")
    @JvmField val UTF_16BE: Charset = Charset.forName("UTF-16BE")
    @JvmField val UTF_16LE: Charset = Charset.forName("UTF-16LE")
    // UTF-32 charsets are optional in Java SE: resolve lazily so a JVM without
    // them can still initialize Charsets and use the required charsets.
    private var utf32: Charset? = null
    private var utf32be: Charset? = null
    private var utf32le: Charset? = null

    @get:JvmName("UTF32")
    val UTF_32: Charset
        get() = utf32 ?: Charset.forName("UTF-32").also { utf32 = it }

    @get:JvmName("UTF32BE")
    val UTF_32BE: Charset
        get() = utf32be ?: Charset.forName("UTF-32BE").also { utf32be = it }

    @get:JvmName("UTF32LE")
    val UTF_32LE: Charset
        get() = utf32le ?: Charset.forName("UTF-32LE").also { utf32le = it }

    @JvmField val US_ASCII: Charset = Charset.forName("US-ASCII")
    @JvmField val ISO_8859_1: Charset = Charset.forName("ISO-8859-1")
}
