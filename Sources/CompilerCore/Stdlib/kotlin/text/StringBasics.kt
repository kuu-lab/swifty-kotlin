package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-717: STDLIB-TEXT-FN-010. KSwiftK's general String indexing helpers are
// scalar-oriented, so UTF-16 code point counting stays a runtime bridge.
// The bridges take CharSequence as a plain parameter, not a receiver:
// `external fun <interface-type>.member()` corrupts itable dispatch for that
// interface's other members (see KUU-523 / KSP-717 PR notes) — no existing
// bundled source declares an external extension on an interface receiver,
// and adding one here reproducibly broke `for (c in someString)` iteration
// (CharSequence.length/get dispatch). A top-level parameter avoids it.

@KsSymbolName("__kk_string_codePointCount")
internal external fun __kk_string_codePointCount(cs: CharSequence): Int

@KsSymbolName("__kk_string_codePointCount_from")
internal external fun __kk_string_codePointCount_from(cs: CharSequence, startIndex: Int): Int

@KsSymbolName("__kk_string_codePointCount_range")
internal external fun __kk_string_codePointCount_range(cs: CharSequence, startIndex: Int, endIndex: Int): Int

public fun CharSequence.codePointCount(): Int = __kk_string_codePointCount(this)

public fun CharSequence.codePointCount(startIndex: Int): Int = __kk_string_codePointCount_from(this, startIndex)

public fun CharSequence.codePointCount(startIndex: Int = 0, endIndex: Int): Int =
    __kk_string_codePointCount_range(this, startIndex, endIndex)

public fun String.repeat(count: Int): String {
    if (count < 0) throw IllegalArgumentException("Count 'n' must be non-negative, but was $count.")
    val sb = StringBuilder()
    var i = 0
    while (i < count) { sb.append(this); i += 1 }
    return sb.toString()
}

public fun CharSequence.repeat(n: Int): String {
    if (n < 0) throw IllegalArgumentException("Count 'n' must be non-negative, but was $n.")

    return when (n) {
        0 -> ""
        1 -> this.toString()
        else -> {
            when (length) {
                0 -> ""
                1 -> {
                    val char = this[0]
                    val sb = StringBuilder(n)
                    var i = 0
                    while (i < n) {
                        sb.append(char)
                        i += 1
                    }
                    sb.toString()
                }
                else -> {
                    val sb = StringBuilder(n * length)
                    var i = 1
                    while (i <= n) {
                        sb.append(this)
                        i += 1
                    }
                    sb.toString()
                }
            }
        }
    }
}

public fun String.reversed(): String {
    val len = this.length
    val sb = StringBuilder()
    var i = len - 1
    while (i >= 0) { sb.append(this[i]); i -= 1 }
    return sb.toString()
}

public fun CharSequence.reversed(): CharSequence {
    val source = StringBuilder(this.length)
    source.append(this)
    val content = source.toString()
    val sb = StringBuilder()
    var i = content.length - 1
    while (i >= 0) {
        val current = content[i]
        if (i > 0 && (current.isLowSurrogate() || current.isHighSurrogate())) {
            val previous = content[i - 1]
            if (current.isLowSurrogate() && previous.isHighSurrogate()) {
                val pair = CharArray(2)
                pair[0] = previous
                pair[1] = current
                sb.append(pair)
                i -= 2
                continue
            } else if (current.isHighSurrogate() && previous.isLowSurrogate()) {
                val pair = CharArray(2)
                pair[0] = current
                pair[1] = previous
                sb.append(pair)
                i -= 2
                continue
            }
        }
        sb.append(current)
        i -= 1
    }
    return sb
}

public fun String.padStart(length: Int, padChar: Char = ' '): String {
    val padding = length - this.length
    if (padding <= 0) return this
    val sb = StringBuilder()
    var i = 0
    while (i < padding) { sb.append(padChar); i += 1 }
    sb.append(this)
    return sb.toString()
}

public fun String.padEnd(length: Int, padChar: Char = ' '): String {
    val padding = length - this.length
    if (padding <= 0) return this
    val sb = StringBuilder()
    sb.append(this)
    var i = 0
    while (i < padding) { sb.append(padChar); i += 1 }
    return sb.toString()
}
