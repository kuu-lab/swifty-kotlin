package java.nio.charset

import java.util.Locale
import java.util.SortedMap
import java.util.TreeMap
import kotlin.internal.KsSymbolName
import kotlin.text.Charsets

// Native Charset values are source objects. Only the private codec boundary
// consumes the Int tag; a public Charset is never passed as that raw word.
public class Charset internal constructor(internal val tag: Int) : Comparable<Charset> {
    public fun name(): String = charsetName(tag)

    public fun aliases(): Set<String> = when (name()) {
        "UTF-8" -> setOf("UTF8", "unicode-1-1-utf-8")
        "ISO-8859-1" -> setOf("ISO8859_1", "latin1", "l1", "IBM819", "cp819", "ISO8859-1")
        "US-ASCII" -> setOf("ASCII", "iso-ir-6", "ANSI_X3.4-1986", "ISO646-US", "us", "IBM367", "cp367", "csASCII")
        "UTF-16" -> setOf("UTF16", "UnicodeBig")
        "UTF-16BE" -> setOf("UTF_16BE", "X-UTF-16BE", "UnicodeBigUnmarked")
        "UTF-16LE" -> setOf("UTF_16LE", "X-UTF-16LE", "UnicodeLittleUnmarked")
        "UTF-32" -> setOf("UTF32")
        "UTF-32BE" -> setOf("UTF_32BE", "X-UTF-32BE")
        "UTF-32LE" -> setOf("UTF_32LE", "X-UTF-32LE")
        else -> emptySet()
    }

    public fun displayName(): String = name()

    public fun displayName(locale: Locale): String = name()

    public val isRegistered: Boolean
        get() = true

    public fun canEncode(): Boolean = true

    public fun contains(other: Charset): Boolean {
        val ownName = name()
        val otherName = other.name()
        if (ownName == otherName) return true
        if (ownName.startsWith("UTF-")) return true
        return (ownName == "ISO-8859-1" && otherName == "US-ASCII")
    }

    public override fun compareTo(other: Charset): Int =
        name().uppercase().compareTo(other.name().uppercase())

    override fun equals(other: Any?): Boolean =
        other is Charset && name().equals(other.name(), ignoreCase = true)

    override fun hashCode(): Int = name().uppercase().hashCode()

    public override fun toString(): String = name()

    public companion object {
        /**
         * Native defaults to UTF-8, matching Kotlin String and stream encoding.
         * The host locale and JVM file.encoding property do not select a codec.
         */
        public fun defaultCharset(): Charset = Charsets.UTF_8

        /**
         * Returns the charsets supported by the bundled native codecs, keyed
         * by their canonical names in natural string order.
         */
        public fun availableCharsets(): SortedMap<String, Charset> {
            val charsets = TreeMap<String, Charset>()
            val available = listOf(
                Charsets.UTF_8,
                Charsets.ISO_8859_1,
                Charsets.US_ASCII,
                Charsets.UTF_16,
                Charsets.UTF_16BE,
                Charsets.UTF_16LE,
                Charsets.UTF_32,
                Charsets.UTF_32BE,
                Charsets.UTF_32LE
            )
            for (charset in available) charsets.put(charset.name(), charset)
            return charsets
        }

        public fun isSupported(charsetName: String): Boolean {
            return try {
                forName(charsetName)
                true
            } catch (failure: IllegalArgumentException) {
                false
            }
        }

        public fun forName(charsetName: String, fallback: Charset?): Charset? {
            return try {
                forName(charsetName)
            } catch (failure: IllegalArgumentException) {
                fallback
            }
        }

        public fun forName(charsetName: String): Charset {
            if (charsetName.isEmpty()) throw IllegalCharsetNameException(charsetName)
            fun letterOrDigit(c: Char): Boolean = c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9'
            if (!letterOrDigit(charsetName[0])) throw IllegalCharsetNameException(charsetName)
            for (c in charsetName) {
                if (!letterOrDigit(c) && c != '-' && c != '+' && c != ':' && c != '_' && c != '.') {
                    throw IllegalCharsetNameException(charsetName)
                }
            }
            return when (charsetName.uppercase()) {
                "UTF-8", "UTF8", "UNICODE-1-1-UTF-8" -> Charsets.UTF_8
                "ISO-8859-1", "ISO8859-1", "ISO_8859_1", "ISO_8859-1", "ISO_8859-1:1987", "ISO8859_1", "LATIN1", "L1", "CP819", "IBM819", "819", "CSISOLATIN1" -> Charsets.ISO_8859_1
                "US-ASCII", "ASCII", "ANSI_X3.4-1986", "ISO646-US", "ANSI_X3.4-1968", "US", "ISO_646.IRV:1991", "ISO-IR-6", "IBM367", "CP367", "CSASCII", "646" -> Charsets.US_ASCII
                "UTF-16", "UTF16", "UNICODE", "UNICODEBIG" -> Charsets.UTF_16
                "UTF-16BE", "UTF_16BE", "ISO-10646-UCS-2", "X-UTF-16BE", "UNICODEBIGUNMARKED" -> Charsets.UTF_16BE
                "UTF-16LE", "UTF_16LE", "X-UTF-16LE", "UNICODELITTLEUNMARKED" -> Charsets.UTF_16LE
                "UTF-32", "UTF32" -> Charsets.UTF_32
                "UTF-32BE", "UTF_32BE", "X-UTF-32BE" -> Charsets.UTF_32BE
                "UTF-32LE", "UTF_32LE", "X-UTF-32LE" -> Charsets.UTF_32LE
                else -> throw UnsupportedCharsetException(charsetName)
            }
        }
    }
}

@KsSymbolName("__kk_charset_name")
private external fun charsetName(tag: Int): String
