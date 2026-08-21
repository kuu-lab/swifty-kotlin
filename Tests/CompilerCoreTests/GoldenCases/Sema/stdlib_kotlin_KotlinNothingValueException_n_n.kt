package golden.sema

fun constructKotlinNothingValueException(cause: Throwable): Throwable {
    KotlinNothingValueException()
    KotlinNothingValueException("message")
    KotlinNothingValueException(cause)
    return KotlinNothingValueException("message and cause", cause)
}
