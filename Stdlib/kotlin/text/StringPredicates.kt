package kotlin.text

import kswiftk.internal.*

// MARK: - Nullable String helpers

fun String?.isNullOrEmpty(): Boolean = __string_isNullOrEmpty_flat(this)

fun String?.isNullOrBlank(): Boolean = __string_isNullOrBlank_flat(this)

fun String?.orEmpty(): String = this ?: ""

// MARK: - Empty/Blank checks (runtime-backed)

fun String.isEmpty(): Boolean = __string_isEmpty_flat(this)

fun String.isNotEmpty(): Boolean = __string_isNotEmpty_flat(this)

fun String.isBlank(): Boolean = __string_isBlank_flat(this)

fun String.isNotBlank(): Boolean = __string_isNotBlank_flat(this)

// MARK: - Comparison (runtime-backed)

operator fun String.compareTo(other: String): Int = __string_compareTo_flat(this, other)

fun String.compareTo(other: String, ignoreCase: Boolean): Int =
    __string_compareToIgnoreCase_flat(this, other, ignoreCase)

// MARK: - Character access (runtime-backed)

operator fun String.get(index: Int): Char {
    if (index < 0 || index >= __string_struct_get_length(this)) {
        throw IndexOutOfBoundsException("String index out of range: $index")
    }
    return __string_get_flat(this, index)
}

fun String.getOrNull(index: Int): Char? = __string_getOrNull_flat(this, index)

fun String.first(): Char = __string_first_flat(this)

fun String.last(): Char = __string_last_flat(this)

fun String.single(): Char = __string_single_flat(this)

fun String.firstOrNull(): Char? = __string_firstOrNull_flat(this)

fun String.lastOrNull(): Char? = __string_lastOrNull_flat(this)

fun String.singleOrNull(): Char? = __string_singleOrNull_flat(this)

// MARK: - String lookup (runtime-backed)

fun String.startsWith(prefix: String): Boolean = __string_startsWith_flat(this, prefix)

fun String.endsWith(suffix: String): Boolean = __string_endsWith_flat(this, suffix)

operator fun String.contains(other: String): Boolean = __string_contains_flat(this, other)

fun String.contains(other: String, ignoreCase: Boolean): Boolean =
    __string_contains_ignoreCase_flat(this, other, ignoreCase)

fun String.indexOf(other: String): Int = __string_indexOf_flat(this, other)

fun String.indexOf(string: String, startIndex: Int): Int =
    __string_indexOf_from_flat(this, string, startIndex)

fun String.indexOf(string: String, startIndex: Int, ignoreCase: Boolean): Int =
    __string_indexOf_ignoreCase_flat(this, string, startIndex, ignoreCase)

fun String.lastIndexOf(other: String): Int = __string_lastIndexOf_flat(this, other)

fun String.lastIndexOf(string: String, startIndex: Int): Int =
    __string_lastIndexOf_ignoreCase_flat(this, string, startIndex, false)

fun String.lastIndexOf(string: String, startIndex: Int, ignoreCase: Boolean): Int =
    __string_lastIndexOf_ignoreCase_flat(this, string, startIndex, ignoreCase)
