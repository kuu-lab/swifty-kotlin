fun main() {
    val noArg = OutOfMemoryError()
    val withMessage = OutOfMemoryError("message")

    println(noArg is Error)
    println(noArg.message ?: "null")
    println(withMessage.message ?: "null")
}
