/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Decoding adapted from Kotlin 2.3.10 commonMain/kotlin/io/encoding/Base64.kt.
 */
package kotlin.io.encoding

import kotlin.internal.KsSymbolName

// KSP-482: Base64 encode/decode/padding logic migrated to pure Kotlin.
// Migration source: Sources/Runtime/RuntimeBase64.swift (25 kk_base64_* @_cdecl entries, all deleted).
// Only the OutputStream.encodingWith stream wrapper stays as a runtime bridge
// (renamed kk_output_stream_encodingWith -> __kk_output_stream_encodingWith),
// since it wraps a stateful native OutputStream sink.

private const val STANDARD_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
private const val URL_SAFE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
// RFC 2045 (MIME) wraps at 76 chars; RFC 1421 (PEM) wraps at 64. Real Kotlin
// keeps these distinct (`lineLengthMime`/`lineLengthPem`) even though both
// otherwise share the standard alphabet.
private const val MIME_LINE_LENGTH = 76
private const val PEM_LINE_LENGTH = 64
private const val BASE64_BITS_PER_BYTE = 8
private const val BASE64_BITS_PER_SYMBOL = 6
private const val BASE64_PAD_SYMBOL: Byte = 61

public open class Base64 internal constructor(
    internal val alphabetChars: String,
    // 0 means "do not wrap"; a positive value is the line-wrap width.
    private val lineLength: Int
) {
    internal var paddingOption: PaddingOption = PaddingOption.PRESENT

    public enum class PaddingOption {
        PRESENT,
        ABSENT,
        PRESENT_OPTIONAL,
        ABSENT_OPTIONAL,
    }

    public open fun withPadding(option: PaddingOption): Base64 {
        val copy = Base64(alphabetChars, lineLength)
        copy.paddingOption = option
        return copy
    }

    public open fun encode(source: ByteArray, startIndex: Int = 0, endIndex: Int = source.size): String {
        checkSourceBounds(source.size, startIndex, endIndex)
        val raw = encodeRaw(source, startIndex, endIndex)
        return if (lineLength > 0) wrapAtLineLength(raw) else raw
    }

    public open fun encodeToByteArray(
        source: ByteArray,
        startIndex: Int = 0,
        endIndex: Int = source.size
    ): ByteArray = encode(source, startIndex, endIndex).encodeToByteArray()

    public open fun encodeIntoByteArray(
        source: ByteArray,
        destination: ByteArray,
        destinationOffset: Int = 0,
        startIndex: Int = 0,
        endIndex: Int = source.size
    ): Int {
        val encoded = encodeToByteArray(source, startIndex, endIndex)
        encoded.copyInto(destination, destinationOffset)
        return encoded.size
    }

    @IgnorableReturnValue
    public open fun <A : Appendable> encodeToAppendable(
        source: ByteArray,
        destination: A,
        startIndex: Int = 0,
        endIndex: Int = source.size
    ): A {
        destination.append(encode(source, startIndex, endIndex))
        return destination
    }

    public open fun decode(source: ByteArray, startIndex: Int = 0, endIndex: Int = source.size): ByteArray {
        checkSourceBounds(source.size, startIndex, endIndex)
        val destination = ByteArray(decodedSize(source, startIndex, endIndex))
        decodeImpl(source, destination, 0, startIndex, endIndex)
        return destination
    }

    public open fun decodeIntoByteArray(
        source: ByteArray,
        destination: ByteArray,
        destinationOffset: Int = 0,
        startIndex: Int = 0,
        endIndex: Int = source.size
    ): Int {
        checkSourceBounds(source.size, startIndex, endIndex)
        checkDestinationBounds(destination.size, destinationOffset, decodedSize(source, startIndex, endIndex))
        return decodeImpl(source, destination, destinationOffset, startIndex, endIndex)
    }

    public open fun decode(source: CharSequence, startIndex: Int = 0, endIndex: Int = source.length): ByteArray {
        return decode(charsToBytes(source, startIndex, endIndex))
    }

    public open fun decodeIntoByteArray(
        source: CharSequence,
        destination: ByteArray,
        destinationOffset: Int = 0,
        startIndex: Int = 0,
        endIndex: Int = source.length
    ): Int {
        return decodeIntoByteArray(charsToBytes(source, startIndex, endIndex), destination, destinationOffset)
    }

    private fun encodeRaw(source: ByteArray, startIndex: Int, endIndex: Int): String {
        val sb = StringBuilder()
        val addPadding = paddingOption == PaddingOption.PRESENT || paddingOption == PaddingOption.PRESENT_OPTIONAL
        var i = startIndex
        while (i + 2 < endIndex) {
            val b0 = source[i].toInt() and 0xFF
            val b1 = source[i + 1].toInt() and 0xFF
            val b2 = source[i + 2].toInt() and 0xFF
            sb.append(alphabetChars[b0 shr 2])
            sb.append(alphabetChars[((b0 and 0x03) shl 4) or (b1 shr 4)])
            sb.append(alphabetChars[((b1 and 0x0F) shl 2) or (b2 shr 6)])
            sb.append(alphabetChars[b2 and 0x3F])
            i += 3
        }
        val remaining = endIndex - i
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
        if (raw.length <= lineLength) return raw
        val sb = StringBuilder()
        var index = 0
        while (index < raw.length) {
            val end = if (index + lineLength < raw.length) index + lineLength else raw.length
            if (index != 0) sb.append("\r\n")
            sb.append(raw.substring(index, end))
            index = end
        }
        return sb.toString()
    }

    private fun decodeImpl(
        source: ByteArray,
        destination: ByteArray,
        destinationOffset: Int,
        startIndex: Int,
        endIndex: Int
    ): Int {
        var payload = 0
        var byteStart = -BASE64_BITS_PER_BYTE
        var sourceIndex = startIndex
        var destinationIndex = destinationOffset
        var hasPadding = false

        while (sourceIndex < endIndex) {
            if (byteStart == -BASE64_BITS_PER_BYTE && sourceIndex + 3 < endIndex) {
                val symbol1 = decodeSymbol(source[sourceIndex++].toInt() and 0xFF)
                val symbol2 = decodeSymbol(source[sourceIndex++].toInt() and 0xFF)
                val symbol3 = decodeSymbol(source[sourceIndex++].toInt() and 0xFF)
                val symbol4 = decodeSymbol(source[sourceIndex++].toInt() and 0xFF)
                val bits = (symbol1 shl 18) or (symbol2 shl 12) or (symbol3 shl 6) or symbol4
                if (bits >= 0) { // all base64 symbols
                    destination[destinationIndex++] = (bits shr 16).toByte()
                    destination[destinationIndex++] = (bits shr 8).toByte()
                    destination[destinationIndex++] = bits.toByte()
                    continue
                }
                sourceIndex -= 4
            }

            val symbol = source[sourceIndex].toInt() and 0xFF
            val symbolBits = decodeSymbol(symbol)
            if (symbolBits < 0) {
                if (symbolBits == -2) {
                    hasPadding = true
                    sourceIndex = handlePaddingSymbol(source, sourceIndex, endIndex, byteStart)
                    break
                } else if (lineLength > 0) {
                    sourceIndex += 1
                    continue
                } else {
                    throw IllegalArgumentException("Invalid symbol '${symbol.toChar()}'(${symbol.toString(radix = 8)}) at index $sourceIndex")
                }
            } else {
                sourceIndex += 1
            }

            payload = (payload shl BASE64_BITS_PER_SYMBOL) or symbolBits
            byteStart += BASE64_BITS_PER_SYMBOL

            if (byteStart >= 0) {
                destination[destinationIndex++] = (payload ushr byteStart).toByte()

                payload = payload and ((1 shl byteStart) - 1)
                byteStart -= BASE64_BITS_PER_BYTE
            }
        }

        // pad or end of input

        if (byteStart == -BASE64_BITS_PER_BYTE + BASE64_BITS_PER_SYMBOL) { // dangling single symbol, incorrectly encoded
            throw IllegalArgumentException("The last unit of input does not have enough bits")
        }
        if (byteStart != -BASE64_BITS_PER_BYTE && !hasPadding && paddingOption == PaddingOption.PRESENT) {
            throw IllegalArgumentException("The padding option is set to PRESENT, but the input is not properly padded")
        }
        if (payload != 0) { // the pad bits are non-zero
            throw IllegalArgumentException("The pad bits must be zeros")
        }

        sourceIndex = skipIllegalSymbolsIfMime(source, sourceIndex, endIndex)
        if (sourceIndex < endIndex) {
            val symbol = source[sourceIndex].toInt() and 0xFF
            throw IllegalArgumentException("Symbol '${symbol.toChar()}'(${symbol.toString(radix = 8)}) at index ${sourceIndex - 1} is prohibited after the pad character")
        }

        return destinationIndex - destinationOffset
    }

    private fun decodedSize(source: ByteArray, startIndex: Int, endIndex: Int): Int {
        var symbols = endIndex - startIndex
        if (symbols == 0) {
            return 0
        }
        if (symbols == 1) {
            throw IllegalArgumentException("Input should have at least 2 symbols for Base64 decoding, startIndex: $startIndex, endIndex: $endIndex")
        }
        if (lineLength > 0) {
            for (index in startIndex until endIndex) {
                val symbol = source[index].toInt() and 0xFF
                val symbolBits = decodeSymbol(symbol)
                if (symbolBits < 0) {
                    if (symbolBits == -2) {
                        symbols -= endIndex - index
                        break
                    }
                    symbols--
                }
            }
        } else if (source[endIndex - 1] == BASE64_PAD_SYMBOL) {
            symbols--
            if (source[endIndex - 2] == BASE64_PAD_SYMBOL) {
                symbols--
            }
        }
        return ((symbols.toLong() * BASE64_BITS_PER_SYMBOL) / BASE64_BITS_PER_BYTE).toInt() // conversion due to possible Int overflow
    }

    private fun charsToBytes(source: CharSequence, startIndex: Int, endIndex: Int): ByteArray {
        checkSourceBounds(source.length, startIndex, endIndex)

        val byteArray = ByteArray(endIndex - startIndex)
        var length = 0
        for (index in startIndex until endIndex) {
            val symbol = source[index].code
            if (symbol <= 0xFF) {
                byteArray[length++] = symbol.toByte()
            } else {
                // the replacement byte must be an illegal symbol
                // so that mime skips it and basic throws with correct index
                byteArray[length++] = 0x3F
            }
        }
        return byteArray
    }

    private fun handlePaddingSymbol(source: ByteArray, padIndex: Int, endIndex: Int, byteStart: Int): Int {
        return when (byteStart) {
            -BASE64_BITS_PER_BYTE -> // =
                throw IllegalArgumentException("Redundant pad character at index $padIndex")
            -BASE64_BITS_PER_BYTE + BASE64_BITS_PER_SYMBOL -> // x=, dangling single symbol
                padIndex + 1
            -BASE64_BITS_PER_BYTE + 2 * BASE64_BITS_PER_SYMBOL - BASE64_BITS_PER_BYTE -> { // xx=
                checkPaddingIsAllowed(padIndex)
                val secondPadIndex = skipIllegalSymbolsIfMime(source, padIndex + 1, endIndex)
                if (secondPadIndex == endIndex || source[secondPadIndex] != BASE64_PAD_SYMBOL) {
                    throw IllegalArgumentException("Missing one pad character at index $secondPadIndex")
                }
                secondPadIndex + 1
            }
            -BASE64_BITS_PER_BYTE + 3 * BASE64_BITS_PER_SYMBOL - 2 * BASE64_BITS_PER_BYTE -> { // xxx=
                checkPaddingIsAllowed(padIndex)
                padIndex + 1
            }
            else ->
                error("Unreachable")
        }
    }

    private fun checkPaddingIsAllowed(padIndex: Int) {
        if (paddingOption == PaddingOption.ABSENT) {
            throw IllegalArgumentException(
                "The padding option is set to ABSENT, but the input has a pad character at index $padIndex"
            )
        }
    }

    private fun skipIllegalSymbolsIfMime(source: ByteArray, startIndex: Int, endIndex: Int): Int {
        if (lineLength == 0) {
            return startIndex
        }
        var sourceIndex = startIndex
        while (sourceIndex < endIndex) {
            val symbol = source[sourceIndex].toInt() and 0xFF
            if (decodeSymbol(symbol) != -1) {
                return sourceIndex
            }
            sourceIndex += 1
        }
        return sourceIndex
    }

    private fun decodeSymbol(symbol: Int): Int =
        if (symbol == 61) -2 else alphabetChars.indexOf(symbol.toChar())

    private fun checkDestinationBounds(destinationSize: Int, destinationOffset: Int, capacityNeeded: Int) {
        if (destinationOffset < 0 || destinationOffset > destinationSize || capacityNeeded > destinationSize - destinationOffset) {
            throw IndexOutOfBoundsException("The destination array does not have enough capacity")
        }
    }

    private fun checkSourceBounds(sourceSize: Int, startIndex: Int, endIndex: Int) {
        if (startIndex < 0 || endIndex > sourceSize) {
            throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, size: $sourceSize")
        }
        if (startIndex > endIndex) {
            throw IllegalArgumentException("startIndex: $startIndex must be less than or equal to endIndex: $endIndex")
        }
    }

    public companion object Default : Base64(STANDARD_ALPHABET, 0) {
        public val UrlSafe: Base64 = Base64(URL_SAFE_ALPHABET, 0)
        public val Mime: Base64 = Base64(STANDARD_ALPHABET, MIME_LINE_LENGTH)
        public val Pem: Base64 = Base64(STANDARD_ALPHABET, PEM_LINE_LENGTH)
    }
}

public val Base64.PaddingOption.entries: kotlin.enums.EnumEntries<Base64.PaddingOption>
    get() = enumEntries<Base64.PaddingOption>()

@KsSymbolName("__kk_output_stream_encodingWith")
private external fun __outputStreamEncodingWith(
    stream: java.io.OutputStream,
    alphabet: String,
    addPadding: Boolean
): java.io.OutputStream

public fun java.io.OutputStream.encodingWith(base64: Base64): java.io.OutputStream =
    __outputStreamEncodingWith(
        this,
        base64.alphabetChars,
        base64.paddingOption == Base64.PaddingOption.PRESENT || base64.paddingOption == Base64.PaddingOption.PRESENT_OPTIONAL
    )
