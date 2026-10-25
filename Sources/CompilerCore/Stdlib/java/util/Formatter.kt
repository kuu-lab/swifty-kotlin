package java.util

import kotlin.text.format

/** A string-backed subset of java.util.Formatter. */
public class Formatter {
    private var result: String = ""

    public fun format(format: String, vararg arguments: Any?): Formatter {
        result += format.format(*arguments)
        return this
    }

    public fun format(locale: Locale?, format: String, vararg arguments: Any?): Formatter {
        result += format.format(locale, *arguments)
        return this
    }

    public fun flush() {}

    public fun close() {}

    override fun toString(): String = result
}
