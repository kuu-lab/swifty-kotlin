package kotlin.io.encoding

import kotlin.internal.KsSymbolName

// KSP-482: Base64 encode/decode/padding logic migrated to pure Kotlin.
// Migration source: Sources/Runtime/RuntimeBase64.swift (25 kk_base64_* @_cdecl entries, all deleted).
// Only the OutputStream.encodingWith stream wrapper stays as a runtime bridge
// (renamed kk_output_stream_encodingWith -> __kk_output_stream_encodingWith),
// since it wraps a stateful native OutputStream sink.

private const val STANDARD_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
private const val URL_SAFE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
private const val MIME_LINE_LENGTH = 76

public open class Base64 internal constructor(
    private val alphabetChars: String,
    private val wrapLines: Boolean
) {
    private var padding: PaddingOption = PaddingOption.PRESENT

    public enum class PaddingOption {
        PRESENT,
        ABSENT,
        PRESENT_OPTIONAL,
        ABSENT_OPTIONAL,
    }

    public open fun withPadding(option: PaddingOption): Base64 {
        val copy = Base64(alphabetChars, wrapLines)
        copy.padding = option
        return copy
    }

    public open fun encode(source: ByteArray): String {
        val raw = encodeRaw(source)
        return if (wrapLines) wrapAtLineLength(raw) else raw
    }

    public open fun decode(source: String): ByteArray {
        val sanitized = if (wrapLines) filterToAlphabet(source) else source
        return decodeRaw(sanitized)
    }

    public open fun encodeToByteArray(source: ByteArray): ByteArray = encode(source).encodeToByteArray()

    public open fun decodeFromByteArray(source: ByteArray): ByteArray = decode(source.decodeToString())

    private fun encodeRaw(source: ByteArray): String {
        val sb = StringBuilder()
        val addPadding = padding == PaddingOption.PRESENT || padding == PaddingOption.PRESENT_OPTIONAL
        var i = 0
        while (i + 2 < source.size) {
            val b0 = source[i].toInt() and 0xFF
            val b1 = source[i + 1].toInt() and 0xFF
            val b2 = source[i + 2].toInt() and 0xFF
            sb.append(alphabetChars[b0 shr 2])
            sb.append(alphabetChars[((b0 and 0x03) shl 4) or (b1 shr 4)])
            sb.append(alphabetChars[((b1 and 0x0F) shl 2) or (b2 shr 6)])
            sb.append(alphabetChars[b2 and 0x3F])
            i += 3
        }
        val remaining = source.size - i
        if (remaining == 1) {
            val b0 = source[i].toInt() and 0xFF
            sb.append(alphabetChars[b0 shr 2])
            sb.append(alphabetChars[(b0 and 0x03) shl 4])
            if (addPadding) sb.append("==")
        } else if (remaining == 2) {
            val b0 = source[i].toInt() and 0xFF
            val b1 = source[i + 1].toInt() and 0xFF
            sb.append(alphabetChars[b0 shr 2])
            sb.append(alphabetChars[((b0 and 0x03) shl 4) or (b1 shr 4)])
            sb.append(alphabetChars[(b1 and 0x0F) shl 2])
            if (addPadding) sb.append("=")
        }
        return sb.toString()
    }

    private fun wrapAtLineLength(raw: String): String {
        if (raw.length <= MIME_LINE_LENGTH) return raw
        val sb = StringBuilder()
        var index = 0
        while (index < raw.length) {
            val end = if (index + MIME_LINE_LENGTH < raw.length) index + MIME_LINE_LENGTH else raw.length
            if (index != 0) sb.append("\r\n")
            sb.append(raw.substring(index, end))
            index = end
        }
        return sb.toString()
    }

    // RFC 2045 MIME decoders ignore every character outside the alphabet
    // (whitespace, CRLF, control characters), rather than rejecting them.
    private fun filterToAlphabet(source: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < source.length) {
            val c = source[i]
            if (c == '=' || alphabetChars.indexOf(c) >= 0) {
                sb.append(c)
            }
            i += 1
        }
        return sb.toString()
    }

    private fun decodeRaw(source: String): ByteArray {
        val hasPadding = source.indexOf('=') >= 0
        when (padding) {
            PaddingOption.PRESENT ->
                if (!hasPadding && source.length % 4 != 0) {
                    throw IllegalArgumentException("Missing base64 padding")
                }
            PaddingOption.ABSENT ->
                if (hasPadding) {
                    throw IllegalArgumentException("Unexpected base64 padding in ABSENT mode")
                }
            PaddingOption.PRESENT_OPTIONAL, PaddingOption.ABSENT_OPTIONAL -> {
                // Accept either form.
            }
        }

        var end = source.length
        while (end > 0 && source[end - 1] == '=') end -= 1

        val bytes = ArrayList<Byte>()
        var buffer = 0
        var bitsCollected = 0
        var i = 0
        while (i < end) {
            val c = source[i]
            val value = alphabetChars.indexOf(c)
            if (value < 0) {
                throw IllegalArgumentException("Illegal base64 character in input")
            }
            buffer = (buffer shl 6) or value
            bitsCollected += 6
            if (bitsCollected >= 8) {
                bitsCollected -= 8
                bytes.add(((buffer shr bitsCollected) and 0xFF).toByte())
            }
            i += 1
        }
        return bytes.toByteArray()
    }

    public companion object {
        public val Default: Base64 = Base64(STANDARD_ALPHABET, false)
        public val UrlSafe: Base64 = Base64(URL_SAFE_ALPHABET, false)
        public val Mime: Base64 = Base64(STANDARD_ALPHABET, true)
        public val Pem: Base64 = Base64(STANDARD_ALPHABET, true)
    }
}

public fun String.decodingWith(codec: Base64): ByteArray = codec.decode(this)

@KsSymbolName("__kk_output_stream_encodingWith")
private external fun __outputStreamEncodingWith(stream: java.io.OutputStream, base64: Base64): java.io.OutputStream

public fun java.io.OutputStream.encodingWith(base64: Base64): java.io.OutputStream =
    __outputStreamEncodingWith(this, base64)
