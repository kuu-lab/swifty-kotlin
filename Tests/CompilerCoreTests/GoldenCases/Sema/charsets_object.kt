// STDLIB-TEXT-TYPE-005: Charsets object — verifies all nine charset constants
// (UTF_8, UTF_16, US_ASCII, ISO_8859_1, UTF_16BE, UTF_16LE, UTF_32, UTF_32BE,
// UTF_32LE) are resolved as kotlin.text.Charset values from the singleton object.
// The decodeToString(charset) overload itself is covered by
// bytearray_decode_charset.kt; this case owns the constant surface.
fun main() {
    val utf8: Charset = Charsets.UTF_8
    val utf16: Charset = Charsets.UTF_16
    val usAscii: Charset = Charsets.US_ASCII
    val iso88591: Charset = Charsets.ISO_8859_1
    val utf16be: Charset = Charsets.UTF_16BE
    val utf16le: Charset = Charsets.UTF_16LE
    val utf32: Charset = Charsets.UTF_32
    val utf32be: Charset = Charsets.UTF_32BE
    val utf32le: Charset = Charsets.UTF_32LE
    println(utf8)
    println(utf16)
    println(usAscii)
    println(iso88591)
    println(utf16be)
    println(utf16le)
    println(utf32)
    println(utf32be)
    println(utf32le)
}
