package golden.sema

fun catchKotlinNothingValue(): String =
    try { throw KotlinNothingValueException("bad") }
    catch (e: KotlinNothingValueException) { "caught" }
