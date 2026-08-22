fun main() {
    val noArg = ArrayIndexOutOfBoundsException()
    val message = ArrayIndexOutOfBoundsException("bad index")

    println(noArg.message ?: "null")
    println(message.message ?: "bad index")
    println(noArg is IndexOutOfBoundsException)
    println(message is RuntimeException)
    println(message is Throwable)
    println(noArg is ArrayIndexOutOfBoundsException)

    try {
        throw ArrayIndexOutOfBoundsException("thrown")
    } catch (e: ArrayIndexOutOfBoundsException) {
        println("caught: ${e.message ?: "null"}")
    }
}
