package kotlin.text

// KSP-481: HexFormat class + toHexString/hexTo* extension functions, fully
// Kotlinized (no native bridge). Migration source: Sources/Runtime/RuntimeHexFormat.swift
// (kk_hexformat_default/create/upperCase/bytes, kk_int_toHexString, kk_long_toHexString,
// kk_bytearray_toHexString, kk_string_hexTo{Int,Short,Long,UByte,UShort,UInt,ULong,
// ByteArray,UByteArray}). Sema stub HeaderHelpers+SyntheticHexFormatStubs.swift no
// longer registers any HexFormat symbol; this file is the sole dispatch path.
//
// Simplified surface: HexFormat is a single flat class (no nested NumberHexFormat /
// BytesHexFormat), matching the pre-existing RuntimeHexFormatBox model. The `bytes`
// and `number` properties both alias `this` so the real-Kotlin chaining syntax
// (`format.bytes.byteSeparator = ...`, `format.number.prefix = ...`) still resolves,
// even though every field lives directly on HexFormat. Custom formats are built via
// the ordinary named-argument constructor (`HexFormat(upperCase = true, ...)`) rather
// than a `HexFormat { }` builder lambda: neither a top-level `fun HexFormat(...)`
// (collides with the class name -- KSWIFTK-SEMA-0001) nor a constructor whose body
// invokes its own function-typed parameter (codegen emits an undefined `_paramName`
// symbol) currently works for bundled source. Flagged for follow-up separately.
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
public class HexFormat(
    public var upperCase: Boolean = false,
    public var byteSeparator: String = "",
    public var prefix: String = "",
    public var suffix: String = "",
    public var removeLeadingZeros: Boolean = false,
) {
    /** Chaining alias so `format.bytes.byteSeparator = ...` resolves to this instance. */
    public val bytes: HexFormat
        get() = this

    /** Chaining alias so `format.number.prefix = ...` resolves to this instance. */
    public val number: HexFormat
        get() = this

    public companion object {
        @ExperimentalStdlibApi
        public val Default: HexFormat = HexFormat()
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
    if (format.removeLeadingZeros) {
        hex = trimLeadingZeros(hex)
    }
    if (format.upperCase) {
        hex = hex.uppercase()
    }
    return format.prefix + hex + format.suffix
}

// ─── toHexString ───────────────────────────────────────────────────────────────

@ExperimentalStdlibApi
public fun Int.toHexString(format: HexFormat = defaultHexFormat()): String =
    applyNumberFormat(hexDigitsOf(this.toLong() and 0xffffffffL, 8), format)

@ExperimentalStdlibApi
public fun Long.toHexString(format: HexFormat = defaultHexFormat()): String =
    applyNumberFormat(hexDigitsOf(this, 16), format)

@ExperimentalStdlibApi
public fun ByteArray.toHexString(format: HexFormat = defaultHexFormat()): String {
    val sb = StringBuilder()
    var i = 0
    while (i < this.size) {
        if (i > 0) {
            sb.append(format.byteSeparator)
        }
        val byteHex = hexDigitsOf(this[i].toLong() and 0xffL, 2)
        sb.append(if (format.upperCase) byteHex.uppercase() else byteHex)
        i += 1
    }
    return sb.toString()
}

// ─── shared decode helpers ─────────────────────────────────────────────────────

private fun stripPrefixSuffix(str: String, format: HexFormat): String {
    var working = str
    val prefix = format.prefix
    val suffix = format.suffix
    if (prefix.isNotEmpty()) {
        if (!working.startsWith(prefix)) {
            throw NumberFormatException("For hex string \"$str\": missing required prefix \"$prefix\"")
        }
        working = working.substring(prefix.length)
    }
    if (suffix.isNotEmpty()) {
        if (!working.endsWith(suffix)) {
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
        if (hex[i].digitToIntOrNull(16) == null) {
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

@ExperimentalStdlibApi
public fun String.hexToInt(format: HexFormat = defaultHexFormat()): Int =
    parseHexNumber(this, format, 8).toInt()

@ExperimentalStdlibApi
public fun String.hexToShort(format: HexFormat = defaultHexFormat()): Short =
    parseHexNumber(this, format, 4).toShort()

@ExperimentalStdlibApi
public fun String.hexToLong(format: HexFormat = defaultHexFormat()): Long =
    parseHexNumber(this, format, 16)

// ─── hexTo* (unsigned) ───────────────────────────────────────────────────────

// NOTE: converts directly from the (always non-negative, width-limited) Long
// accumulator rather than via `.toByte()`/`.toShort()`/`.toInt()` first: narrowing
// to a signed type that happens to go negative, then widening-unsigned from that,
// currently produces a value that still prints/compares as negative.
// Flagged for follow-up separately.

@ExperimentalStdlibApi
public fun String.hexToUByte(format: HexFormat = defaultHexFormat()): UByte =
    parseHexNumber(this, format, 2).toUByte()

@ExperimentalStdlibApi
public fun String.hexToUShort(format: HexFormat = defaultHexFormat()): UShort =
    parseHexNumber(this, format, 4).toUShort()

@ExperimentalStdlibApi
public fun String.hexToUInt(format: HexFormat = defaultHexFormat()): UInt =
    parseHexNumber(this, format, 8).toUInt()

@ExperimentalStdlibApi
public fun String.hexToULong(format: HexFormat = defaultHexFormat()): ULong =
    parseHexNumber(this, format, 16).toULong()

// ─── hexToByteArray / hexToUByteArray ────────────────────────────────────────

private fun parseByteValues(receiver: String, format: HexFormat): List<Int> {
    val separator = format.byteSeparator
    val hexString = if (separator.isNotEmpty()) receiver.replace(separator, "") else receiver
    if (hexString.length % 2 != 0) {
        throw NumberFormatException(
            "For hex string \"$receiver\": expected an even number of hexadecimal digits"
        )
    }
    val values = ArrayList<Int>(hexString.length / 2)
    var index = 0
    while (index < hexString.length) {
        val highDigit = hexString[index].digitToIntOrNull(16)
        val lowDigit = hexString[index + 1].digitToIntOrNull(16)
        if (highDigit == null || lowDigit == null) {
            throw NumberFormatException("For hex string \"$receiver\": not a valid hexadecimal string")
        }
        val high: Int = highDigit!!
        val low: Int = lowDigit!!
        values.add((high shl 4) or low)
        index += 2
    }
    return values
}

@ExperimentalStdlibApi
public fun String.hexToByteArray(format: HexFormat = defaultHexFormat()): ByteArray {
    val values = parseByteValues(this, format)
    return ByteArray(values.size) { values[it].toByte() }
}

@ExperimentalStdlibApi
public fun String.hexToUByteArray(format: HexFormat = defaultHexFormat()): UByteArray {
    val values = parseByteValues(this, format)
    return UByteArray(values.size) { values[it].toUByte() }
}
