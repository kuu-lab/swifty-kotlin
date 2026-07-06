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

public fun String?.isNullOrEmpty(): Boolean {
    return (this ?: "").isEmpty()
}

public fun String?.isNullOrBlank(): Boolean {
    return (this ?: "").isBlank()
}

public fun String?.orEmpty(): String {
    return this ?: ""
}

public fun CharSequence.lines(): List<String> {
    val source = ksp401StringFromCharSequence(this).replace("\r\n", "\n").replace("\r", "\n")
    if (source.length == 0) return mutableListOf<String>()

    val result = mutableListOf<String>()
    var start = 0
    while (start <= source.length) {
        val index = source.indexOf("\n", start)
        if (index == -1) {
            result.add(source.substring(start))
            return result
        }
        result.add(source.substring(start, index))
        start = index + 1
    }
    return result
}

public fun CharSequence.lineSequence(): Sequence<String> {
    return ksp401StringFromCharSequence(this).replace("\r\n", "\n").replace("\r", "\n").splitToSequence("\n")
}
