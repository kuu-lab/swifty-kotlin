package golden.sema

fun catchTypeCast(): String =
    try { throw TypeCastException("bad type cast") }
    catch (e: TypeCastException) { "caught" }
