package kotlin.text

// KSP-481: HexFormat class + toHexString/hexTo* extension functions, fully
// Kotlinized (no native bridge). Migration source: Sources/Runtime/RuntimeHexFormat.swift
// (kk_hexformat_default/create/upperCase/bytes, kk_int_toHexString, kk_long_toHexString,
// kk_bytearray_toHexString, kk_string_hexTo{Int,Short,Long,UByte,UShort,UInt,ULong,
// ByteArray,UByteArray}). Sema stub HeaderHelpers+SyntheticHexFormatStubs.swift no
// longer registers any HexFormat symbol; this file is the sole dispatch path.
//
// The public surface follows the Kotlin 2.3 stdlib model: HexFormat owns immutable
// BytesHexFormat and NumberHexFormat values, while Builder owns their mutable builders.
// The legacy named-argument constructor is retained for existing KSwiftK callers and
// maps its flat options into the corresponding nested formats.
//
// All character scanning below uses index-based `while` loops rather than
// `for (ch in someString)` or `for (i in 0 until n)`: both mistype the loop-bound
// element when a `Char` member function is subsequently called on it. Likewise,
// null-checked locals are re-bound via `!!` rather than relied upon via smart-cast,
// since `if (a == null || b == null) throw ...` does not narrow `a`/`b` afterwards.
// (Same constraints already observed and worked around in Stdlib/kotlin/uuid/Uuid.kt.)
//
// Default-valued parameters below call `defaultHexFormat()` (a plain top-level
// function) rather than `HexFormat.Default` or `HexFormat()` directly: a default
// parameter value that itself constructs a class instance or reads a companion
// property currently emits an undefined symbol (e.g. `_Default`) at link time.
// Routing through an ordinary function call sidesteps that gap. Flagged for
// follow-up separately.

/**
 * Formatting options for [Int.toHexString], [Long.toHexString], [ByteArray.toHexString]
 * and the corresponding `hexTo*` decoding functions.
 */
public class HexFormat internal constructor(
    public val upperCase: Boolean,
    public val bytes: BytesHexFormat,
    public val number: NumberHexFormat,
) {
    /** Compatibility constructor for the pre-nested KSwiftK HexFormat surface. */
    public constructor(
        upperCase: Boolean = false,
        byteSeparator: String = "",
        prefix: String = "",
        suffix: String = "",
        removeLeadingZeros: Boolean = false,
    ) : this(
        upperCase = upperCase,
        bytes = BytesHexFormat(
            bytesPerLine = Int.MAX_VALUE,
            bytesPerGroup = Int.MAX_VALUE,
            groupSeparator = "  ",
            byteSeparator = byteSeparator,
            bytePrefix = "",
            byteSuffix = "",
        ),
        number = NumberHexFormat(
            prefix = prefix,
            suffix = suffix,
            removeLeadingZeros = removeLeadingZeros,
            minLength = 1,
        ),
    )

    override fun toString(): String {
        val result = StringBuilder()
        result.append("HexFormat(\n")
        result.append("    upperCase = ").append(upperCase).append(",\n")
        result.append("    bytes = ").append(bytes.toString()).append(",\n")
        result.append("    number = ").append(number.toString()).append("\n")
        result.append(")")
        return result.toString()
    }

    /** Immutable formatting options for byte arrays. */
    public class BytesHexFormat internal constructor(
        public val bytesPerLine: Int,
        public val bytesPerGroup: Int,
        public val groupSeparator: String,
        public val byteSeparator: String,
        public val bytePrefix: String,
        public val byteSuffix: String,
    ) {
        override fun toString(): String {
            val result = StringBuilder()
            result.append("BytesHexFormat(\n")
            result.append("    bytesPerLine = ").append(bytesPerLine).append(",\n")
            result.append("    bytesPerGroup = ").append(bytesPerGroup).append(",\n")
            result.append("    groupSeparator = \"").append(groupSeparator).append("\",\n")
            result.append("    byteSeparator = \"").append(byteSeparator).append("\",\n")
            result.append("    bytePrefix = \"").append(bytePrefix).append("\",\n")
            result.append("    byteSuffix = \"").append(byteSuffix).append("\"\n")
            result.append(")")
            return result.toString()
        }

        /** Mutable options used while building a [BytesHexFormat]. */
        public class Builder @PublishedApi internal constructor() {
            public var bytesPerLine: Int = Int.MAX_VALUE
            public var bytesPerGroup: Int = Int.MAX_VALUE
            public var groupSeparator: String = "  "
            public var byteSeparator: String = ""
            public var bytePrefix: String = ""
            public var byteSuffix: String = ""

            @PublishedApi
            internal fun build(): BytesHexFormat = BytesHexFormat(
                bytesPerLine = bytesPerLine,
                bytesPerGroup = bytesPerGroup,
                groupSeparator = groupSeparator,
                byteSeparator = byteSeparator,
                bytePrefix = bytePrefix,
                byteSuffix = byteSuffix,
            )
        }
    }

    /** Immutable formatting options for numeric values. */
    public class NumberHexFormat internal constructor(
        public val prefix: String,
        public val suffix: String,
        public val removeLeadingZeros: Boolean,
        public val minLength: Int,
    ) {
        override fun toString(): String {
            val result = StringBuilder()
            result.append("NumberHexFormat(\n")
            result.append("    prefix = \"").append(prefix).append("\",\n")
            result.append("    suffix = \"").append(suffix).append("\",\n")
            result.append("    removeLeadingZeros = ").append(removeLeadingZeros).append(",\n")
            result.append("    minLength = ").append(minLength).append("\n")
            result.append(")")
            return result.toString()
        }

        /** Mutable options used while building a [NumberHexFormat]. */
        public class Builder @PublishedApi internal constructor() {
            public var prefix: String = ""
            public var suffix: String = ""
            public var removeLeadingZeros: Boolean = false
            public var minLength: Int = 1

            @PublishedApi
            internal fun build(): NumberHexFormat = NumberHexFormat(
                prefix = prefix,
                suffix = suffix,
                removeLeadingZeros = removeLeadingZeros,
                minLength = minLength,
            )
        }
    }

    /** Mutable root builder used to assemble a [HexFormat]. */
    public class Builder @PublishedApi internal constructor() {
        public var upperCase: Boolean = false
        public val bytes: HexFormat.BytesHexFormat.Builder = BytesHexFormat.Builder()
        public val number: HexFormat.NumberHexFormat.Builder = NumberHexFormat.Builder()

        public inline fun bytes(builderAction: HexFormat.BytesHexFormat.Builder.() -> Unit) {
            bytes.builderAction()
        }

        public inline fun number(builderAction: HexFormat.NumberHexFormat.Builder.() -> Unit) {
            number.builderAction()
        }

        @PublishedApi
        internal fun build(): HexFormat = HexFormat(
            upperCase = upperCase,
            bytes = bytes.build(),
            number = number.build(),
        )
    }

    public companion object {
        public val Default: HexFormat
            get() = defaultHexFormat()

        public val UpperCase: HexFormat
            get() = HexFormat(upperCase = true)
    }
}

private fun defaultHexFormat(): HexFormat = HexFormat()

// ─── shared encode helpers ─────────────────────────────────────────────────────

private const val HEX_DIGITS: String = "0123456789abcdef"

private fun hexDigitsOf(value: Long, digitCount: Int): String {
    val sb = StringBuilder()
    var shift = (digitCount - 1) * 4
    while (shift >= 0) {
        val digit = ((value ushr shift) and 0xfL).toInt()
        sb.append(HEX_DIGITS[digit])
        shift -= 4
    }
    return sb.toString()
}

/** Drops leading `'0'` characters, always leaving at least one digit behind. */
private fun trimLeadingZeros(hex: String): String {
    var start = 0
    while (start < hex.length - 1 && hex[start] == '0') {
        start += 1
    }
    return hex.substring(start)
}

private fun applyNumberFormat(rawHex: String, format: HexFormat): String {
    var hex = rawHex
    val number = format.number
    if (hex.length < number.minLength) {
        hex = "0".repeat(number.minLength - hex.length) + hex
    } else if (number.removeLeadingZeros && hex.length > number.minLength) {
        hex = trimLeadingZeros(hex)
        if (hex.length < number.minLength) {
            hex = "0".repeat(number.minLength - hex.length) + hex
        }
    }
    if (format.upperCase) {
        hex = hex.uppercase()
    }
    return number.prefix + hex + number.suffix
}

// ─── toHexString ───────────────────────────────────────────────────────────────

public fun Int.toHexString(format: HexFormat = defaultHexFormat()): String =
    applyNumberFormat(hexDigitsOf(this.toLong() and 0xffffffffL, 8), format)

public fun Long.toHexString(format: HexFormat = defaultHexFormat()): String =
    applyNumberFormat(hexDigitsOf(this, 16), format)

public fun ByteArray.toHexString(format: HexFormat = defaultHexFormat()): String =
    toHexString(0, size, format)

public fun ByteArray.toHexString(
    startIndex: Int = 0,
    endIndex: Int = size,
    format: HexFormat = defaultHexFormat()
): String {
    if (startIndex < 0 || endIndex > size) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, size: $size")
    }
    if (startIndex > endIndex) {
        throw IllegalArgumentException("startIndex: $startIndex > endIndex: $endIndex")
    }
    checkFormattedByteLength(endIndex - startIndex, format.bytes)
    val sb = StringBuilder()
    val bytes = format.bytes
    var index = startIndex
    while (index < endIndex) {
        val position = index - startIndex
        if (position > 0) {
            val previousLine = (position - 1) / bytes.bytesPerLine
            val currentLine = position / bytes.bytesPerLine
            if (currentLine != previousLine) {
                sb.append('\n')
            } else {
                val positionInLine = position % bytes.bytesPerLine
                val previousGroup = (positionInLine - 1) / bytes.bytesPerGroup
                val currentGroup = positionInLine / bytes.bytesPerGroup
                if (currentGroup != previousGroup) {
                    sb.append(bytes.groupSeparator as CharSequence)
                } else {
                    sb.append(bytes.byteSeparator as CharSequence)
                }
            }
        }
        sb.append(bytes.bytePrefix as CharSequence)
        val byteHex = hexDigitsOf(this[index].toLong() and 0xffL, 2)
        sb.append(if (format.upperCase) byteHex.uppercase() else byteHex)
        sb.append(bytes.byteSuffix as CharSequence)
        index += 1
    }
    return sb.toString()
}

private fun checkedHexLength(length: Long): Long {
    if (length > Int.MAX_VALUE.toLong()) {
        throw IllegalArgumentException("The resulting string length is too large")
    }
    return length
}

private fun checkFormattedByteLength(count: Int, bytes: HexFormat.BytesHexFormat) {
    if (count == 0) return
    val lineSeparators = (count - 1) / bytes.bytesPerLine
    val fullLines = count / bytes.bytesPerLine
    val lastLineSize = count % bytes.bytesPerLine
    val groupSeparators = fullLines.toLong() * ((bytes.bytesPerLine - 1) / bytes.bytesPerGroup) +
        if (lastLineSize == 0) 0L else ((lastLineSize - 1) / bytes.bytesPerGroup).toLong()
    val byteSeparators = count.toLong() - 1 - lineSeparators - groupSeparators
    var length = checkedHexLength(count.toLong() * 2)
    length = checkedHexLength(length + count.toLong() * bytes.bytePrefix.length)
    length = checkedHexLength(length + count.toLong() * bytes.byteSuffix.length)
    length = checkedHexLength(length + groupSeparators * bytes.groupSeparator.length)
    length = checkedHexLength(length + byteSeparators * bytes.byteSeparator.length)
    checkedHexLength(length + lineSeparators)
}

// ─── shared decode helpers ─────────────────────────────────────────────────────

private fun asciiHexDigitOrNull(character: Char): Int? {
    if (character >= '0' && character <= '9') return character.code - '0'.code
    if (character >= 'a' && character <= 'f') return character.code - 'a'.code + 10
    if (character >= 'A' && character <= 'F') return character.code - 'A'.code + 10
    return null
}

private fun stripPrefixSuffix(str: String, format: HexFormat): String {
    var working = str
    val prefix = format.number.prefix
    val suffix = format.number.suffix
    if (prefix.isNotEmpty()) {
        if (!working.startsWith(prefix as CharSequence, ignoreCase = true)) {
            throw NumberFormatException("For hex string \"$str\": missing required prefix \"$prefix\"")
        }
        working = working.substring(prefix.length)
    }
    if (suffix.isNotEmpty()) {
        if (!working.endsWith(suffix as CharSequence, ignoreCase = true)) {
            throw NumberFormatException("For hex string \"$str\": missing required suffix \"$suffix\"")
        }
        working = working.substring(0, working.length - suffix.length)
    }
    return working
}

/**
 * Validates [hex] is all hex digits and fits within [maxDigits], tolerating extra
 * leading zero digits beyond [maxDigits]. Returns the (possibly-trimmed) digit string.
 */
private fun fitHexDigits(original: String, hex: String, maxDigits: Int): String {
    if (hex.isEmpty()) {
        throw NumberFormatException("For hex string \"$original\": not a valid hexadecimal string")
    }
    var i = 0
    while (i < hex.length) {
        if (asciiHexDigitOrNull(hex[i]) == null) {
            throw NumberFormatException("For hex string \"$original\": not a valid hexadecimal string")
        }
        i += 1
    }
    if (hex.length <= maxDigits) {
        return hex
    }
    val excessLength = hex.length - maxDigits
    var j = 0
    while (j < excessLength) {
        if (hex[j] != '0') {
            throw NumberFormatException("For hex string \"$original\": value is too large for the target type")
        }
        j += 1
    }
    return hex.substring(excessLength)
}

private fun hexDigitsToLong(hex: String): Long {
    var acc = 0L
    var i = 0
    while (i < hex.length) {
        acc = (acc shl 4) or hex[i].digitToIntOrNull(16)!!.toLong()
        i += 1
    }
    return acc
}

private fun parseHexNumber(receiver: String, format: HexFormat, maxDigits: Int): Long =
    hexDigitsToLong(fitHexDigits(receiver, stripPrefixSuffix(receiver, format), maxDigits))

// ─── hexTo* (signed) ─────────────────────────────────────────────────────────

public fun String.hexToInt(format: HexFormat = defaultHexFormat()): Int =
    parseHexNumber(this, format, 8).toInt()

public fun String.hexToShort(format: HexFormat = defaultHexFormat()): Short =
    parseHexNumber(this, format, 4).toShort()

public fun String.hexToLong(format: HexFormat = defaultHexFormat()): Long =
    parseHexNumber(this, format, 16)

// ─── hexTo* (unsigned) ───────────────────────────────────────────────────────

// NOTE: converts directly from the (always non-negative, width-limited) Long
// accumulator rather than via `.toByte()`/`.toShort()`/`.toInt()` first: narrowing
// to a signed type that happens to go negative, then widening-unsigned from that,
// currently produces a value that still prints/compares as negative.
// Flagged for follow-up separately.

public fun String.hexToUByte(format: HexFormat = defaultHexFormat()): UByte =
    parseHexNumber(this, format, 2).toUByte()

public fun String.hexToUShort(format: HexFormat = defaultHexFormat()): UShort =
    parseHexNumber(this, format, 4).toUShort()

public fun String.hexToUInt(format: HexFormat = defaultHexFormat()): UInt =
    parseHexNumber(this, format, 8).toUInt()

public fun String.hexToULong(format: HexFormat = defaultHexFormat()): ULong =
    parseHexNumber(this, format, 16).toULong()

// ─── hexToByteArray / hexToUByteArray ────────────────────────────────────────

private fun consumeByteFormatToken(
    receiver: String,
    position: Int,
    token: String,
    message: String,
): Int {
    if (token.isNotEmpty() &&
        (position > receiver.length - token.length ||
            !receiver.regionMatches(position, token, 0, token.length, ignoreCase = true))
    ) {
        throw NumberFormatException("For hex string \"$receiver\": $message")
    }
    return position + token.length
}

private fun consumeByteLineSeparator(receiver: String, position: Int): Int {
    if (position < receiver.length && receiver[position] == '\r') {
        return if (position + 1 < receiver.length && receiver[position + 1] == '\n') {
            position + 2
        } else {
            position + 1
        }
    }
    if (position < receiver.length && receiver[position] == '\n') return position + 1
    throw NumberFormatException("For hex string \"$receiver\": missing line separator")
}

private fun parseByteValues(receiver: String, format: HexFormat): List<Int> {
    if (receiver.isEmpty()) return ArrayList()

    val bytes = format.bytes
    val values = ArrayList<Int>()
    var position = 0
    var index = 0
    while (position < receiver.length) {
        if (index > 0) {
            val previousLine = (index - 1) / bytes.bytesPerLine
            val currentLine = index / bytes.bytesPerLine
            if (currentLine != previousLine) {
                position = consumeByteLineSeparator(receiver, position)
            } else {
                val indexInLine = index % bytes.bytesPerLine
                val previousGroup = (indexInLine - 1) / bytes.bytesPerGroup
                val currentGroup = indexInLine / bytes.bytesPerGroup
                if (currentGroup != previousGroup) {
                    position = consumeByteFormatToken(
                        receiver,
                        position,
                        bytes.groupSeparator,
                        "missing group separator",
                    )
                } else {
                    position = consumeByteFormatToken(
                        receiver,
                        position,
                        bytes.byteSeparator,
                        "missing byte separator",
                    )
                }
            }
        }

        position = consumeByteFormatToken(
            receiver,
            position,
            bytes.bytePrefix,
            "missing byte prefix",
        )
        if (position > receiver.length - 2) {
            throw NumberFormatException("For hex string \"$receiver\": expected two hexadecimal digits per byte")
        }
        val highDigit = asciiHexDigitOrNull(receiver[position])
        val lowDigit = asciiHexDigitOrNull(receiver[position + 1])
        if (highDigit == null || lowDigit == null) {
            throw NumberFormatException("For hex string \"$receiver\": not a valid hexadecimal string")
        }
        val high: Int = highDigit!!
        val low: Int = lowDigit!!
        position += 2
        position = consumeByteFormatToken(
            receiver,
            position,
            bytes.byteSuffix,
            "missing byte suffix",
        )
        values.add((high shl 4) or low)
        index += 1
    }
    return values
}

public fun String.hexToByteArray(format: HexFormat = defaultHexFormat()): ByteArray {
    val values = parseByteValues(this, format)
    return ByteArray(values.size) { values[it].toByte() }
}

@ExperimentalUnsignedTypes
public fun String.hexToUByteArray(format: HexFormat = defaultHexFormat()): UByteArray {
    val values = parseByteValues(this, format)
    return UByteArray(values.size) { values[it].toUByte() }
}
