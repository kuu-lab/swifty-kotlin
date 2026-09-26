import kotlinx.io.*

// Exercises EOFException/require()/request() behavior when a Buffer does not have enough data.

fun main() {
    val buf = Buffer()
    buf.writeByte(1)
    println(buf.request(1))
    println(buf.request(2))

    try {
        buf.readInt()
    } catch (e: EOFException) {
        println("caught: ${e.message}")
    }

    println(buf.size)
    println(buf.readByte())

    try {
        buf.readByte()
    } catch (e: EOFException) {
        println("caught2: ${e.message}")
    }

    try {
        buf.skip(5L)
    } catch (e: EOFException) {
        println("caught3: ${e.message}")
    }

    try {
        buf.require(1L)
    } catch (e: EOFException) {
        println("caught4: ${e.message}")
    }

    println(EOFException("custom").message)
    println(IOException("io custom").message)
    println(IOException().message)
}
