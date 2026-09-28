package kotlin.text

import kotlin.internal.KsSymbolName

// Empty, blank, and line helpers are implemented in bundled Kotlin source.

@PublishedApi
@KsSymbolName("kk_string_isBlank_flat")
internal external fun String.__kkIsBlankFlat(): Boolean

public fun CharSequence.isEmpty(): Boolean = this.length == 0

public fun CharSequence.isNotEmpty(): Boolean = this.length != 0

public fun CharSequence.isBlank(): Boolean {
    var i = 0
    while (i < this.length) {
        if (!this[i].isWhitespace()) return false
        i++
    }
    return true
}

public fun CharSequence.isNotBlank(): Boolean = !isBlank()

public inline fun <C, R> C.ifEmpty(defaultValue: () -> R): R where C : CharSequence, C : R {
    return if (isEmpty()) defaultValue() else this
}

public inline fun <C, R> C.ifBlank(defaultValue: () -> R): R where C : CharSequence, C : R {
    // Generic C receivers lose String's flat representation if length/get are
    // dispatched through CharSequence. Keep flat strings on their dedicated
    // runtime bridge; user-defined CharSequence implementations use the itable.
    if (this is String) {
        return if (this.__kkIsBlankFlat()) defaultValue() else this
    }
    var index = 0
    while (index < this.length) {
        if (!this[index].isWhitespace()) return this
        index++
    }
    return defaultValue()
}

public fun CharSequence?.isNullOrEmpty(): Boolean {
    val value = this
    if (value == null) return true
    return value!!.isEmpty()
}

public fun CharSequence?.isNullOrBlank(): Boolean {
    val value = this
    if (value == null) return true
    return value!!.isBlank()
}

public fun String?.orEmpty(): String {
    return this ?: ""
}

public fun String.lines(): List<String> {
    return splitIntoLines()
}

public fun CharSequence.lines(): List<String> {
    return this.toString().splitIntoLines()
}

public fun String.lineSequence(): Sequence<String> {
    return normalizeLineSeparators().splitToSequence("\n")
}

public fun CharSequence.lineSequence(): Sequence<String> {
    return this.toString().normalizeLineSeparators().splitToSequence("\n")
}
