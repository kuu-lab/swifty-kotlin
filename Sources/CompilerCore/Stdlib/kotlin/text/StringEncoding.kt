package kotlin.text

import kotlin.internal.KsSymbolName

public class Charset internal constructor(internal val tag: Int)

public object Charsets {
    @KsSymbolName("__kk_charset_utf_8")
    private external fun __utf_8(): Int
    public val UTF_8: Charset = Charset(__utf_8())

    @KsSymbolName("__kk_charset_iso_8859_1")
    private external fun __iso_8859_1(): Int
    public val ISO_8859_1: Charset = Charset(__iso_8859_1())

    @KsSymbolName("__kk_charset_us_ascii")
    private external fun __us_ascii(): Int
    public val US_ASCII: Charset = Charset(__us_ascii())

    @KsSymbolName("__kk_charset_utf_16")
    private external fun __utf_16(): Int
    public val UTF_16: Charset = Charset(__utf_16())

    @KsSymbolName("__kk_charset_utf_16be")
    private external fun __utf_16be(): Int
    public val UTF_16BE: Charset = Charset(__utf_16be())

    @KsSymbolName("__kk_charset_utf_16le")
    private external fun __utf_16le(): Int
    public val UTF_16LE: Charset = Charset(__utf_16le())

    @KsSymbolName("__kk_charset_utf_32")
    private external fun __utf_32(): Int
    public val UTF_32: Charset = Charset(__utf_32())

    @KsSymbolName("__kk_charset_utf_32be")
    private external fun __utf_32be(): Int
    public val UTF_32BE: Charset = Charset(__utf_32be())

    @KsSymbolName("__kk_charset_utf_32le")
    private external fun __utf_32le(): Int
    public val UTF_32LE: Charset = Charset(__utf_32le())
}

@KsSymbolName("__kk_string_toByteArray_flat")
private external fun String.__kk_string_toByteArray_flat(): ByteArray

@KsSymbolName("__kk_string_toByteArray_charset_flat")
private external fun String.__kk_string_toByteArray_charset_flat(charsetTag: Int): ByteArray

@KsSymbolName("__kk_string_encodeToByteArray_flat")
private external fun String.__kk_string_encodeToByteArray_flat(): ByteArray

@KsSymbolName("__kk_string_encodeToByteArray_range_flat")
private external fun String.__kk_string_encodeToByteArray_range_flat(startIndex: Int, endIndex: Int): ByteArray

@KsSymbolName("__kk_string_encodeToByteArray_charset_flat")
private external fun String.__kk_string_encodeToByteArray_charset_flat(charsetID: Int): ByteArray

@KsSymbolName("__kk_bytearray_decodeToString")
private external fun ByteArray.__kk_bytearray_decodeToString(): String

@KsSymbolName("__kk_bytearray_decodeToString_charset")
private external fun ByteArray.__kk_bytearray_decodeToString_charset(charsetId: Int): String

@KsSymbolName("__kk_bytearray_decodeToString_range")
private external fun ByteArray.__kk_bytearray_decodeToString_range(startIndex: Int, endIndex: Int): String

@KsSymbolName("__kk_bytearray_decodeToString_range_throw")
private external fun ByteArray.__kk_bytearray_decodeToString_range_throw(
    startIndex: Int,
    endIndex: Int,
    throwOnInvalidSequence: Boolean
): String

public fun String.toByteArray(): ByteArray =
    this.__kk_string_toByteArray_flat()

public fun String.toByteArray(charset: Charset): ByteArray =
    this.__kk_string_toByteArray_charset_flat(charset.tag)

public fun String.toByteArray(startIndex: Int, endIndex: Int): ByteArray =
    this.encodeToByteArray(startIndex, endIndex)

public fun String.encodeToByteArray(): ByteArray =
    this.__kk_string_encodeToByteArray_flat()

public fun String.encodeToByteArray(charset: Charset): ByteArray =
    this.__kk_string_encodeToByteArray_charset_flat(charset.tag)

public fun String.encodeToByteArray(startIndex: Int, endIndex: Int): ByteArray {
    if (startIndex < 0 || endIndex > this.length || startIndex > endIndex) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, length: ${this.length}")
    }
    return this.__kk_string_encodeToByteArray_range_flat(startIndex, endIndex)
}

public fun ByteArray.decodeToString(): String =
    this.__kk_bytearray_decodeToString()

public fun ByteArray.decodeToString(charset: Charset): String =
    this.__kk_bytearray_decodeToString_charset(charset.tag)

public fun ByteArray.decodeToString(startIndex: Int, endIndex: Int): String {
    if (startIndex < 0 || endIndex > this.size || startIndex > endIndex) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, size: ${this.size}")
    }
    return this.__kk_bytearray_decodeToString_range(startIndex, endIndex)
}

public fun ByteArray.decodeToString(
    startIndex: Int,
    endIndex: Int,
    throwOnInvalidSequence: Boolean
): String {
    if (startIndex < 0 || endIndex > this.size || startIndex > endIndex) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, size: ${this.size}")
    }
    return this.__kk_bytearray_decodeToString_range_throw(startIndex, endIndex, throwOnInvalidSequence)
}
