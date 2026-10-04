package golden.sema

fun constructOutOfMemoryError(): OutOfMemoryError {
    OutOfMemoryError()
    return OutOfMemoryError("message")
}
