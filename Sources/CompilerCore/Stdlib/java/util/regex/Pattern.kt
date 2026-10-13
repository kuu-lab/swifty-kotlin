package java.util.regex

import kotlin.text.Regex

/** A Kotlin-backed subset of `java.util.regex.Pattern`. */
public class Pattern internal constructor(private val regex: Regex) {
    public fun matcher(input: CharSequence): Matcher = Matcher(regex, input.toString())

    public companion object {
        public fun compile(pattern: String): Pattern = Pattern(Regex(pattern))

        internal fun fromRegex(regex: Regex): Pattern = Pattern(regex)
    }
}
