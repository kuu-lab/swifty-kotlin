package kotlin.text

typealias Charset = java.nio.charset.Charset

// Reads map to java.nio.charset.StandardCharsets static fields (see
// prepareTextLibrary).
object Charsets {
    val UTF_8: Charset get() = null!!
    val UTF_16: Charset get() = null!!
    val UTF_16BE: Charset get() = null!!
    val UTF_16LE: Charset get() = null!!
    val US_ASCII: Charset get() = null!!
    val ISO_8859_1: Charset get() = null!!
}
