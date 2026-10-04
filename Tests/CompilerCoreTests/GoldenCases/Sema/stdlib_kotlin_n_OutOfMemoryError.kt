package golden.sema

fun outOfMemoryErrorDefault(): String {
    val e = OutOfMemoryError()
    return e.message ?: "null"
}

fun outOfMemoryErrorMessage(): String {
    val e = OutOfMemoryError("out of memory")
    return e.message ?: "null"
}
