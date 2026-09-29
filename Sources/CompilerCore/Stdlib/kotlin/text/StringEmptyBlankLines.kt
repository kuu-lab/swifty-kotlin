package kotlin.text

import kotlin.internal.KsSymbolName

// Empty, blank, and line helpers are implemented in bundled Kotlin source.

@KsSymbolName("kk_string_isBlank_flat")
private external fun String.__kkStringIsBlankFlat(): Boolean

private fun CharSequence.__kkIsBlank(): Boolean {
    // String uses a flat aggregate ABI and has no object receiver that can be
    // registered in the CharSequence itable. Keep custom CharSequence
    // implementations on their indexed interface path, while routing an
    // erased String receiver through the existing flat runtime bridge.
    if (this is String) return this.__kkStringIsBlankFlat()

    var i = 0
    while (i < this.length) {
        if (!this[i].isWhitespace()) return false
        i++
    }
    return true
}

public fun CharSequence.isEmpty(): Boolean = this.length == 0

public fun CharSequence.isNotEmpty(): Boolean = this.length != 0

public fun CharSequence.isBlank(): Boolean = this.__kkIsBlank()

public fun CharSequence.isNotBlank(): Boolean = !this.__kkIsBlank()

public inline fun <C, R> C.ifEmpty(defaultValue: () -> R): R where C : CharSequence, C : R {
    val value: CharSequence = this
    return if (value.isEmpty()) defaultValue() else this
}

public inline fun <C, R> C.ifBlank(defaultValue: () -> R): R where C : CharSequence, C : R {
    val value: CharSequence = this
    return if (value.__kkIsBlank()) defaultValue() else this
}

public fun CharSequence?.isNullOrEmpty(): Boolean {
    val value = this
    if (value == null) return true
    return value!!.isEmpty()
}

public fun CharSequence?.isNullOrBlank(): Boolean {
    val value = this
    if (value == null) return true
    return value!!.__kkIsBlank()
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
