package kotlin.text

import java.nio.charset.Charset
import kotlin.jvm.JvmField

object Charsets {
    @JvmField val UTF_8: Charset = Charset.forName("UTF-8")
    @JvmField val UTF_16: Charset = Charset.forName("UTF-16")
    @JvmField val UTF_16BE: Charset = Charset.forName("UTF-16BE")
    @JvmField val UTF_16LE: Charset = Charset.forName("UTF-16LE")
    @JvmField val US_ASCII: Charset = Charset.forName("US-ASCII")
    @JvmField val ISO_8859_1: Charset = Charset.forName("ISO-8859-1")
}
