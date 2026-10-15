@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package kotlinx.serialization.json

import kotlin.math.floor
import kotlin.math.pow

public sealed class JsonElement

public abstract class JsonPrimitive : JsonElement() {
    public abstract val isString: Boolean
    public abstract val content: String

    public override fun toString(): String = content
}

internal class JsonLiteral internal constructor(
    body: Any,
    public override val isString: Boolean
) : JsonPrimitive() {
    public override val content: String = body.toString()

    public override fun toString(): String = if (isString) content.toJsonQuotedString() else content

    public override fun equals(other: Any?): Boolean =
        other is JsonLiteral && isString == other.isString && content == other.content

    public override fun hashCode(): Int = 31 * (if (isString) 1231 else 1237) + content.hashCode()
}

public object JsonNull : JsonPrimitive() {
    public override val isString: Boolean = false
    public override val content: String = "null"
}

public fun JsonPrimitive(value: Boolean?): JsonPrimitive =
    if (value == null) JsonNull else JsonLiteral(value, isString = false)

public fun JsonPrimitive(value: Number?): JsonPrimitive =
    if (value == null) JsonNull else JsonLiteral(value, isString = false)

public fun JsonPrimitive(value: String?): JsonPrimitive =
    if (value == null) JsonNull else JsonLiteral(value, isString = true)

@Suppress("FunctionName", "UNUSED_PARAMETER")
public fun JsonPrimitive(value: Nothing?): JsonNull = JsonNull

public fun JsonPrimitive(value: UByte): JsonPrimitive = JsonPrimitive(value.toULong())

public fun JsonPrimitive(value: UShort): JsonPrimitive = JsonPrimitive(value.toULong())

public fun JsonPrimitive(value: UInt): JsonPrimitive = JsonPrimitive(value.toULong())

public fun JsonPrimitive(value: ULong): JsonPrimitive = JsonLiteral(value.toString(), isString = false)

public val JsonElement.jsonPrimitive: JsonPrimitive
    get() = this as? JsonPrimitive ?: error("JsonPrimitive")

public val JsonElement.jsonNull: JsonNull
    get() = this as? JsonNull ?: error("JsonNull")

public val JsonPrimitive.int: Int
    get() {
        val result = parseLongImpl()
        if (result < Int.MIN_VALUE.toLong() || result > Int.MAX_VALUE.toLong()) {
            throw NumberFormatException(content + " is not an Int")
        }
        return result.toInt()
    }

public val JsonPrimitive.intOrNull: Int?
    get() {
        val result = try {
            parseLongImpl()
        } catch (_: NumberFormatException) {
            return null
        }
        if (result < Int.MIN_VALUE.toLong() || result > Int.MAX_VALUE.toLong()) return null
        return result.toInt()
    }

public val JsonPrimitive.long: Long
    get() = parseLongImpl()

public val JsonPrimitive.longOrNull: Long?
    get() = try {
        parseLongImpl()
    } catch (_: NumberFormatException) {
        null
    }

public val JsonPrimitive.double: Double
    get() = content.toDouble()

public val JsonPrimitive.doubleOrNull: Double?
    get() = content.toDoubleOrNull()

public val JsonPrimitive.float: Float
    get() = content.toFloat()

public val JsonPrimitive.floatOrNull: Float?
    get() = content.toFloatOrNull()

public val JsonPrimitive.boolean: Boolean
    get() = content.toJsonBooleanOrNull() ?: throw IllegalStateException(toString() + " does not represent a Boolean")

public val JsonPrimitive.booleanOrNull: Boolean?
    get() = content.toJsonBooleanOrNull()

public val JsonPrimitive.contentOrNull: String?
    get() = if (this === JsonNull) null else content

private fun JsonElement.error(expected: String): Nothing =
    throw IllegalArgumentException("Element " + this::class.toString() + " is not a " + expected)

private fun JsonPrimitive.parseLongImpl(): Long {
    val source = content
    var current = 0
    while (current < source.length && source[current].isJsonWhitespace()) current++
    val start = current
    if (current >= source.length) throwJsonNumberFormat(source, "EOF", current)

    var accumulator = 0L
    var exponentAccumulator = 0L
    var isNegative = false
    var isExponentPositive = true
    var hasExponent = false
    while (current < source.length) {
        val character = source[current]
        if ((character == 'e' || character == 'E') && !hasExponent) {
            if (current == start) throwJsonNumberFormat(source, "Unexpected symbol " + character + " in numeric literal", start)
            isExponentPositive = true
            hasExponent = true
            current++
            continue
        }
        if (character == '-' && hasExponent) {
            if (current == start) throwJsonNumberFormat(source, "Unexpected symbol '-' in numeric literal", start)
            isExponentPositive = false
            current++
            continue
        }
        if (character == '+' && hasExponent) {
            if (current == start) throwJsonNumberFormat(source, "Unexpected symbol '+' in numeric literal", start)
            isExponentPositive = true
            current++
            continue
        }
        if (character == '-') {
            if (current != start) throwJsonNumberFormat(source, "Unexpected symbol '-' in numeric literal", start)
            isNegative = true
            current++
            continue
        }
        if (!character.isJsonNumericCharacter()) break
        current++
        val digit = character.code - '0'.code
        if (digit !in 0..9) throwJsonNumberFormat(source, "Unexpected symbol '" + character + "' in numeric literal", start)
        if (hasExponent) {
            exponentAccumulator = exponentAccumulator * 10 + digit
            continue
        }
        accumulator = accumulator * 10 - digit
        if (accumulator > 0) throwJsonNumberFormat(source, "Numeric value overflow", current)
    }

    if (start == current || (isNegative && start == current - 1)) {
        throwJsonNumberFormat(source, "Expected numeric literal", start)
    }
    var trailing = current
    while (trailing < source.length && source[trailing].isJsonWhitespace()) trailing++
    if (trailing < source.length) {
        throwJsonNumberFormat(
            source,
            "Expected input to contain a single valid number, but got '" + source[trailing] + "' after it",
            trailing + 1
        )
    }

    if (hasExponent) {
        val exponent = if (isExponentPositive) exponentAccumulator.toDouble() else -exponentAccumulator.toDouble()
        val doubleAccumulator = accumulator.toDouble() * 10.0.pow(exponent)
        if (doubleAccumulator > Long.MAX_VALUE.toDouble() || doubleAccumulator < Long.MIN_VALUE.toDouble()) {
            throwJsonNumberFormat(source, "Numeric value overflow", start)
        }
        if (floor(doubleAccumulator) != doubleAccumulator) {
            throwJsonNumberFormat(source, "Can't convert " + doubleAccumulator + " to Long", start)
        }
        accumulator = doubleAccumulator.toLong()
    }
    return when {
        isNegative -> accumulator
        accumulator == Long.MIN_VALUE -> throwJsonNumberFormat(source, "Numeric value overflow", current)
        else -> -accumulator
    }
}

private fun String.toJsonBooleanOrNull(): Boolean? = when {
    equals("true", ignoreCase = true) -> true
    equals("false", ignoreCase = true) -> false
    else -> null
}

private fun Char.isJsonWhitespace(): Boolean = this == ' ' || this == '\n' || this == '\r' || this == '\t'

private fun Char.isJsonNumericCharacter(): Boolean = code >= 0x20 && this !in ",:[]{}\""

private fun throwJsonNumberFormat(source: String, message: String, offset: Int): Nothing {
    val start = offset - 30
    val end = offset + 30
    val excerpt = if (source.length < 200) {
        source
    } else {
        (if (start <= 0) "" else ".....") + source.substring(start.coerceAtLeast(0), end.coerceAtMost(source.length)) +
            (if (end >= source.length) "" else ".....")
    }
    throw NumberFormatException(
        "Unexpected JSON token at offset " + offset + ": " + message + " at path: $\nJSON input: " + excerpt
    )
}

private fun String.toJsonQuotedString(): String = buildString {
    append('"')
    for (character in this@toJsonQuotedString) {
        when (character) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\b' -> append("\\b")
            '\u000C' -> append("\\f")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> {
                if (character < ' ') {
                    append("\\u")
                    appendHexDigit((character.code shr 12) and 0xF)
                    appendHexDigit((character.code shr 8) and 0xF)
                    appendHexDigit((character.code shr 4) and 0xF)
                    appendHexDigit(character.code and 0xF)
                } else {
                    append(character)
                }
            }
        }
    }
    append('"')
}

private fun StringBuilder.appendHexDigit(value: Int) {
    append("0123456789abcdef"[value])
}
