package kotlin

import kswiftk.internal.*

// MARK: - String struct-based implementation

val String.length: Int
    get() = __string_struct_get_length(this)

val String.indices: IntRange
    get() = 0 until this.length

val String.lastIndex: Int
    get() = this.length - 1

// MARK: - Null checks (pure Kotlin)

fun String?.isNullOrEmpty(): Boolean = this == null || this.isEmpty()

fun String?.isNullOrBlank(): Boolean = this == null || this.isBlank()

fun String?.orEmpty(): String = this ?: ""

// MARK: - Empty/Blank checks (pure Kotlin)

fun String.isEmpty(): Boolean = this.length == 0

fun String.isNotEmpty(): Boolean = this.length > 0

fun String.isBlank(): Boolean {
    for (i in 0 until this.length) {
        val char = __string_get_flat(this, i)
        if (!char.isWhitespace()) {
            return false
        }
    }
    return true
}

fun String.isNotBlank(): Boolean = !this.isBlank()

// MARK: - Comparison (runtime-backed)

operator fun String.compareTo(other: String): Int = __string_compareTo_flat(this, other)

// MARK: - String concatenation (runtime-backed)

operator fun String.plus(other: Any?): String = __string_concat(this, other.toString())

// MARK: - Character access (runtime-backed)

operator fun String.get(index: Int): Char {
    if (index < 0 || index >= this.length) {
        throw IndexOutOfBoundsException("String index out of range: $index")
    }
    return __string_get_flat(this, index)
}
