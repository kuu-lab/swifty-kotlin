fun main() {
    val noArg = IndexOutOfBoundsException()
    val message = IndexOutOfBoundsException("bad index")

    println(noArg.message ?: "null")
    println(message.message ?: "bad index")
    println(noArg is IndexOutOfBoundsException)
    println(message is RuntimeException)
    println(message is Throwable)

    try {
        throw IndexOutOfBoundsException("thrown")
    } catch (e: IndexOutOfBoundsException) {
        println("caught: ${e.message ?: "null"}")
    }
}
