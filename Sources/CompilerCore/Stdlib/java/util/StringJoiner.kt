package java.util

/** Mutable builder for joining strings with a delimiter, prefix, and suffix. */
public class StringJoiner(
    private val delimiter: String,
    private val prefix: String = "",
    private val suffix: String = ""
) {
    private val elements = ArrayList<String>()
    private var emptyValue: String? = null

    public fun add(newElement: String): StringJoiner {
        elements.add(newElement)
        return this
    }

    public fun merge(other: StringJoiner): StringJoiner {
        if (other.elements.isEmpty()) return this
        val merged = if (other.elements.size == 1) {
            other.elements[0]
        } else {
            other.elements.joinToString(other.delimiter)
        }
        elements.add(merged)
        return this
    }

    public fun setEmptyValue(newEmptyValue: String): StringJoiner {
        emptyValue = newEmptyValue
        return this
    }

    public fun length(): Int = toString().length

    override fun toString(): String {
        if (elements.isEmpty()) return emptyValue ?: prefix + suffix
        val builder = StringBuilder()
        builder.append(prefix)
        var first = true
        for (element in elements) {
            if (!first) builder.append(delimiter)
            first = false
            builder.append(element)
        }
        builder.append(suffix)
        return builder.toString()
    }
}
