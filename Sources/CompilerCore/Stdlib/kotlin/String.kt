package kotlin

import kswiftk.internal.*

val String.length: Int
    get() = __string_struct_get_length(this)
