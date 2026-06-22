package kotlin.text

import kswiftk.internal.*

// MARK: - Equality checks (runtime-backed)

fun String.equals(other: String?): Boolean = __string_equals_flat(this, other)

fun String.equals(other: String?, ignoreCase: Boolean): Boolean =
    __string_equalsIgnoreCase_flat(this, other, ignoreCase)

fun String?.contentEquals(other: String?): Boolean = __string_contentEquals_flat(this, other)

fun String?.contentEquals(other: String?, ignoreCase: Boolean): Boolean =
    __string_contentEquals_ignoreCase_flat(this, other, ignoreCase)
