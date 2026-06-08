package kotlin

import kswiftk.internal.*

// MARK: - String struct-based implementation

val String.length: Int
    get() = __string_struct_get_length(this)

val String.indices: IntRange
    get() = 0..this.lastIndex

val String.lastIndex: Int
    get() = this.length - 1

// MARK: - String concatenation (runtime-backed)

operator fun String.plus(other: Any?): String = __string_concat(this, other.toString())
