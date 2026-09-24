const val CHANNEL_MAX_SIZE: Int = 1024 * 1024
const val CR: Byte = '\r'.code.toByte()
const val LF: Byte = '\n'.code.toByte()
const val GREETING: String = "Hello, " + "World!"

fun main() {
    println(CHANNEL_MAX_SIZE)
    println(CR)
    println(LF)
    println(GREETING)
}
