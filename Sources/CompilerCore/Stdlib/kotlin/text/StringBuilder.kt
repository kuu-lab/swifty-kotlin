package kotlin.text

import kotlin.internal.KsSymbolName

/**
 * A mutable sequence of characters backed by the KSwiftK runtime string-builder
 * handle. Public operations are implemented in Kotlin; only the small mutable
 * buffer bridge below crosses into the runtime.
 */
public class StringBuilder {
    constructor()
    constructor(content: String)
    constructor(capacity: Int)

    val length: Int
        get() = __kk_string_builder_length()

    operator fun get(index: Int): Char {
        checkElementIndex(index)
        return toString()[index]
    }

    fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        toString().substring(startIndex, endIndex)

    fun append(value: Char): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: CharSequence?): StringBuilder =
        __kk_string_builder_append_obj(if (value == null) "null" else value as String)

    fun append(value: CharSequence?, startIndex: Int, endIndex: Int): StringBuilder =
        appendRange(if (value == null) "null" else value as String, startIndex, endIndex)

    fun append(value: String?): StringBuilder =
        __kk_string_builder_append_obj(value)

    fun append(value: Boolean): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Int): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Long): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Float): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Double): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(vararg value: Any?): StringBuilder {
        var index = 0
        while (index < value.size) {
            __kk_string_builder_append_obj(value[index].toString())
            index += 1
        }
        return this
    }

    fun appendLine(value: Any?): StringBuilder {
        __kk_string_builder_append_obj(value.toString())
        __kk_string_builder_append_obj("\n")
        return this
    }

    fun appendLine(): StringBuilder {
        __kk_string_builder_append_obj("\n")
        return this
    }

    fun insert(index: Int, value: Any?): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: String?): StringBuilder =
        insertString(index, if (value == null) "null" else value)

    fun insert(index: Int, value: Char): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Boolean): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Int): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Long): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Float): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Double): StringBuilder =
        insertString(index, value.toString())

    fun delete(startIndex: Int, endIndex: Int): StringBuilder {
        checkRange(startIndex, endIndex)
        val current = toString()
        return resetTo(current.substring(0, startIndex) + current.substring(endIndex))
    }

    fun deleteRange(startIndex: Int, endIndex: Int): StringBuilder =
        delete(startIndex, endIndex)

    fun clear(): StringBuilder =
        __kk_string_builder_clear()

    fun reverse(): StringBuilder {
        val current = toString()
        var result = ""
        var index = current.length - 1
        while (index >= 0) {
            result = result + current[index]
            index -= 1
        }
        return resetTo(result)
    }

    fun deleteCharAt(index: Int): StringBuilder {
        checkElementIndex(index)
        val current = toString()
        return resetTo(current.substring(0, index) + current.substring(index + 1))
    }

    fun deleteAt(index: Int): StringBuilder =
        deleteCharAt(index)

    operator fun set(index: Int, value: Char): Unit {
        setCharAt(index, value)
    }

    fun appendRange(value: CharSequence, startIndex: Int, endIndex: Int): StringBuilder {
        append((value as String).substring(startIndex, endIndex))
        return this
    }

    fun insertRange(index: Int, value: CharSequence, startIndex: Int, endIndex: Int): StringBuilder =
        insertString(index, (value as String).substring(startIndex, endIndex))

    fun setRange(startIndex: Int, endIndex: Int, value: String): StringBuilder =
        replaceString(startIndex, endIndex, value, false)

    fun replace(start: Int, end: Int, str: String): StringBuilder =
        replaceString(start, end, str, true)

    fun setCharAt(index: Int, value: Char): Unit {
        checkElementIndex(index)
        replaceString(index, index + 1, value.toString(), false)
    }

    fun capacity(): Int =
        currentLength() + 16

    fun ensureCapacity(minimumCapacity: Int): Unit {
    }

    fun trimToSize(): Unit {
    }

    override fun toString(): String =
        __kk_string_builder_toString()

    private fun insertString(index: Int, value: String): StringBuilder {
        checkInsertIndex(index)
        val current = toString()
        return resetTo(current.substring(0, index) + value + current.substring(index))
    }

    private fun replaceString(startIndex: Int, endIndex: Int, value: String, clampEnd: Boolean): StringBuilder {
        val current = toString()
        val effectiveEnd = if (clampEnd && endIndex > current.length) current.length else endIndex
        if (startIndex < 0 || startIndex > current.length || effectiveEnd < startIndex || effectiveEnd > current.length) {
            throw IndexOutOfBoundsException(
                "startIndex: $startIndex, endIndex: $endIndex, length: ${current.length}"
            )
        }
        return resetTo(current.substring(0, startIndex) + value + current.substring(effectiveEnd))
    }

    private fun resetTo(value: String): StringBuilder {
        __kk_string_builder_clear()
        __kk_string_builder_append_obj(value)
        return this
    }

    private fun checkInsertIndex(index: Int) {
        val currentLength = currentLength()
        if (index < 0 || index > currentLength) {
            throw IndexOutOfBoundsException("index=$index, length=$currentLength")
        }
    }

    private fun checkElementIndex(index: Int) {
        val currentLength = currentLength()
        if (index < 0 || index >= currentLength) {
            throw IndexOutOfBoundsException("index=$index, length=$currentLength")
        }
    }

    private fun checkRange(startIndex: Int, endIndex: Int) {
        val currentLength = currentLength()
        if (startIndex < 0 || startIndex > currentLength || endIndex < startIndex || endIndex > currentLength) {
            throw IndexOutOfBoundsException("startIndex=$startIndex, endIndex=$endIndex, length=$currentLength")
        }
    }

    private fun currentLength(): Int =
        __kk_string_builder_length()

    @KsSymbolName("__kk_string_builder_append_obj")
    private external fun __kk_string_builder_append_obj(value: Any?): StringBuilder

    @KsSymbolName("__kk_string_builder_toString")
    private external fun __kk_string_builder_toString(): String

    @KsSymbolName("__kk_string_builder_length_prop")
    private external fun __kk_string_builder_length(): Int

    @KsSymbolName("__kk_string_builder_clear")
    private external fun __kk_string_builder_clear(): StringBuilder
}

public fun buildString(builderAction: StringBuilder.() -> Unit): String {
    val builder = StringBuilder()
    builder.builderAction()
    return builder.toString()
}

public fun buildString(capacity: Int, builderAction: StringBuilder.() -> Unit): String {
    val builder = StringBuilder(capacity)
    builder.builderAction()
    return builder.toString()
}
