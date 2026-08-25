package kotlin.text

// Empty, blank, and line helpers are implemented in bundled Kotlin source.

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

public fun CharSequence.ifEmpty(defaultValue: () -> String): String {
    if (isEmpty()) return defaultValue()
    return this.toString()
}

public fun CharSequence.ifBlank(defaultValue: () -> String): String {
    if (isBlank()) return defaultValue()
    return this.toString()
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
