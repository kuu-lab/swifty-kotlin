// KUU-3404: constructor arguments must run before the class companion initializer.
val logger = StringBuilder()

inline fun <T> logged(message: String, result: () -> T): T {
    logger.append(message)
    return result()
}

class A(val first: String, val second: String) {
    init { logger.append("A.<init>;") }
    companion object { init { logger.append("A.<clinit>;") } }
}

val local = A(logged("args;") { "O" }, "K")

fun main() {
    println(logger.toString())
}
