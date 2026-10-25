package java.nio.charset

import kotlin.text.Charsets

/** Standard charset constants from `java.nio.charset.StandardCharsets`. */
public class StandardCharsets private constructor() {
    public companion object {
        public val ISO_8859_1: Charset = Charsets.ISO_8859_1
        public val US_ASCII: Charset = Charsets.US_ASCII
        public val UTF_8: Charset = Charsets.UTF_8
        public val UTF_16: Charset = Charsets.UTF_16
        public val UTF_16BE: Charset = Charsets.UTF_16BE
        public val UTF_16LE: Charset = Charsets.UTF_16LE
    }
}
