package kotlin

import kswiftk.internal.*

// String keeps this bridge because its flat aggregate ABI has no object
// receiver to register in the CharSequence itable. Interface-typed
// CharSequence.length reads use the synthetic interface property instead.
val String.length: Int
    get() = __kk_string_struct_get_length(this)
