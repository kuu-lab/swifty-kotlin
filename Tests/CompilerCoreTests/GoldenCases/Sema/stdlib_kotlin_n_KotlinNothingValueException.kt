@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

fun catchKotlinNothingValue(): String =
    try { throw KotlinNothingValueException("bad") }
    catch (e: KotlinNothingValueException) { "caught" }
