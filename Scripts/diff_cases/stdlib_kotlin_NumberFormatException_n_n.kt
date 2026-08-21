fun main() {
    val noArg = NumberFormatException()
    val message = NumberFormatException("bad number")

    println(noArg.message ?: "null")
    println(message.message ?: "bad number")
    println(noArg is NumberFormatException)
    println(message is IllegalArgumentException)
    println(message is RuntimeException)
    println(message is Exception)
    println(message is Throwable)

    try {
        throw NumberFormatException("thrown")
    } catch (e: NumberFormatException) {
        println("caught: ${e.message ?: "null"}")
    }

    try {
        throw NumberFormatException("runtime")
    } catch (e: RuntimeException) {
        println("caught runtime: ${e.message ?: "null"}")
    }

    try {
        throw NumberFormatException("exception")
    } catch (e: Exception) {
        println("caught exception: ${e.message ?: "null"}")
    }
}
