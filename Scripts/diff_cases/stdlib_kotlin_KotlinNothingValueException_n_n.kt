@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

fun main() {
    val cause = Exception("cause")
    val noArg = KotlinNothingValueException()
    val message = KotlinNothingValueException("message")
    val causeOnly = KotlinNothingValueException(cause)
    val messageAndCause = KotlinNothingValueException("message and cause", cause)

    println(noArg.message ?: "null")
    println(message.message ?: "null")
    println(causeOnly.cause?.message ?: "null")
    println(messageAndCause.message ?: "null")
    println(messageAndCause.cause?.message ?: "null")
    println(noArg is RuntimeException)
    println(message is Throwable)
    println(causeOnly is KotlinNothingValueException)
    try {
        throw messageAndCause
    } catch (e: KotlinNothingValueException) {
        println("caught")
    }
}
