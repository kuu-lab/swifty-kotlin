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

// KUU-4474: upstream `JsonArray`/`JsonObject` are public `JsonElement`
// subclasses delegating to List/Map. Without them the sealed `when` over
// `JsonElement` cannot be exhaustive and `is JsonArray`/`is JsonObject`
// checks do not resolve.
// KUU-4474: members are implemented explicitly rather than via `by`
// delegation — delegated forwarders for the search members dispatch through
// itable slots the runtime collection boxes do not register, crashing in
// vtable lookup. Iteration + `==` gives identical semantics.
public class JsonArray(
    private val content: List<JsonElement>
) : JsonElement(), List<JsonElement> {
    override val size: Int get() = content.size

    override fun isEmpty(): Boolean = content.isEmpty()

    override operator fun get(index: Int): JsonElement = content[index]

    override fun iterator(): Iterator<JsonElement> = content.iterator()

    override fun listIterator(): ListIterator<JsonElement> = content.listIterator()

    override fun listIterator(index: Int): ListIterator<JsonElement> = content.listIterator(index)

    override fun subList(fromIndex: Int, toIndex: Int): List<JsonElement> =
        content.subList(fromIndex, toIndex)

    override fun contains(element: JsonElement): Boolean {
        for (candidate in content) {
            if (candidate == element) return true
        }
        return false
    }

    override fun containsAll(elements: Collection<JsonElement>): Boolean {
        for (element in elements) {
            if (!contains(element)) return false
        }
        return true
    }

    override fun indexOf(element: JsonElement): Int {
        var index = 0
        for (candidate in content) {
            if (candidate == element) return index
            index++
        }
        return -1
    }

    override fun lastIndexOf(element: JsonElement): Int {
        var result = -1
        var index = 0
        for (candidate in content) {
            if (candidate == element) result = index
            index++
        }
        return result
    }

    public override fun equals(other: Any?): Boolean =
        other is JsonArray && content == other.content

    public override fun hashCode(): Int = content.hashCode()

    public override fun toString(): String = content.joinToString(",", "[", "]")
}

public class JsonObject(
    private val content: Map<String, JsonElement>
) : JsonElement(), Map<String, JsonElement> {
    override val size: Int get() = content.size

    override val keys: Set<String> get() = content.keys

    override val values: Collection<JsonElement> get() = content.values

    override val entries: Set<Map.Entry<String, JsonElement>> get() = content.entries

    override fun isEmpty(): Boolean = content.isEmpty()

    override operator fun get(key: String): JsonElement? = content[key]

    override fun containsKey(key: String): Boolean = content.keys.contains(key)

    override fun containsValue(value: JsonElement): Boolean {
        for (entry in content.entries) {
            if (entry.value == value) return true
        }
        return false
    }

    public override fun equals(other: Any?): Boolean =
        other is JsonObject && content == other.content

    public override fun hashCode(): Int = content.hashCode()

    public override fun toString(): String = content.entries.joinToString(",", "{", "}") { entry ->
        entry.key.toJsonQuotedString() + ":" + entry.value.toString()
    }
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

public fun jsonArrayOf(vararg elements: JsonElement): JsonArray = JsonArray(elements.asList())

public fun jsonObjectOf(vararg pairs: Pair<String, JsonElement>): JsonObject = JsonObject(mapOf(*pairs))

public val JsonElement.jsonPrimitive: JsonPrimitive
    get() = this as? JsonPrimitive ?: error("JsonPrimitive")

public val JsonElement.jsonNull: JsonNull
    get() = this as? JsonNull ?: error("JsonNull")

public val JsonElement.jsonArray: JsonArray
    get() = this as JsonArray

public val JsonElement.jsonObject: JsonObject
    get() = this as JsonObject

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

internal fun String.toJsonQuotedString(): String = buildString {
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
