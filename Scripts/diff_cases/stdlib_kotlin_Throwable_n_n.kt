fun main() {
    val message: String? = "explicit"
    val root: Throwable = Throwable("root")
    val nullableCause: Throwable? = root
    val nullCause: Throwable? = null
    val noArg = Throwable()
    val messageOnly = Throwable(message)
    val causeOnly = Throwable(nullableCause)
    val nullCauseOnly = Throwable(nullCause)
    val messageCause = Throwable(message, nullableCause)
    val messageNullCause = Throwable(message, nullCause)
    val nested = Throwable(causeOnly)

    println(noArg.message ?: "null")
    println(noArg.cause?.message ?: "null")
    println(messageOnly.message ?: "null")
    println(messageOnly.cause?.message ?: "null")
    println(causeOnly.message ?: "null")
    println(causeOnly.cause?.message ?: "null")
    println(nullCauseOnly.message ?: "null")
    println(nullCauseOnly.cause?.message ?: "null")
    println(messageCause.message ?: "null")
    println(messageCause.cause?.message ?: "null")
    println(messageNullCause.message ?: "null")
    println(messageNullCause.cause?.message ?: "null")
    println(nested.message ?: "null")
    println(nested.cause?.message ?: "null")
}
