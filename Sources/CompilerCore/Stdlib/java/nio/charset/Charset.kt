package java.nio.charset

import kotlin.internal.KsSymbolName

// Native Charset values are source objects. Only the private codec boundary
// consumes the Int tag; a public Charset is never passed as that raw word.
public class Charset internal constructor(internal val tag: Int) {
    public fun name(): String = charsetName(tag)
    public override fun toString(): String = name()

    public companion object {
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
