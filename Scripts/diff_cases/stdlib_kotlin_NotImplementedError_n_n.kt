fun main() {
    val noArg = NotImplementedError()
    val message = NotImplementedError("later")

    println(noArg.message)
    println(message.message)
    println(message is Error)
    try {
        throw message
    } catch (e: NotImplementedError) {
        println(e.message)
    }
}

