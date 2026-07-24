package kotlin.text

import kswiftk.internal.*

// KSP-401: empty/blank/line helpers migrated from Swift Runtime.

private fun ksp401StringFromCharSequence(value: CharSequence): String {
    val builder = StringBuilder()
    var i = 0
    while (i < __string_struct_get_length(value)) {
        builder.append(value[i])
        i++
    }
    return builder.toString()
}

private fun ksp401IsWhitespace(value: Char): Boolean {
    return value == ' ' || value == '\t' || value == '\n' || value == '\r'
}

public fun CharSequence.isEmpty(): Boolean = __string_struct_get_length(this) == 0

public fun CharSequence.isNotEmpty(): Boolean = __string_struct_get_length(this) != 0

public fun CharSequence.isBlank(): Boolean {
    var i = 0
    while (i < __string_struct_get_length(this)) {
        if (!ksp401IsWhitespace(this[i])) return false
        i++
    }
    return true
}

public fun CharSequence.isNotBlank(): Boolean = !isBlank()

public fun CharSequence.ifEmpty(defaultValue: () -> String): String {
    if (isEmpty()) return defaultValue()
    return ksp401StringFromCharSequence(this)
}

public fun CharSequence.ifBlank(defaultValue: () -> String): String {
    if (isBlank()) return defaultValue()
    return ksp401StringFromCharSequence(this)
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

private fun ksp401Lines(source: String): List<String> {
    val result = mutableListOf<String>()
    if (source.length == 0) {
        result.add("")
        return result
    }
    var start = 0
    while (true) {
        val index = source.indexOf("\n", start)
        if (index == -1) {
            result.add(source.substring(start))
            return result
        }
        result.add(source.substring(start, index))
        start = index + 1
    }
}

public fun String.lines(): List<String> {
    return ksp401Lines(this.replace("\r\n", "\n").replace("\r", "\n"))
}

public fun CharSequence.lines(): List<String> {
    return ksp401Lines(ksp401StringFromCharSequence(this).replace("\r\n", "\n").replace("\r", "\n"))
}

public fun String.lineSequence(): Sequence<String> {
    // Normalize platform line endings before splitting so the public helper
    // stays source-backed instead of dispatching to the legacy runtime entry.
    return this.replace("\r\n", "\n").replace("\r", "\n").splitToSequence("\n")
}

public fun CharSequence.lineSequence(): Sequence<String> {
    return ksp401StringFromCharSequence(this).replace("\r\n", "\n").replace("\r", "\n").splitToSequence("\n")
}
