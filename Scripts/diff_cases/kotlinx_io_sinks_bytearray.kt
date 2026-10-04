import kotlinx.io.*

// Sink.write(ByteArray) extension forms (the upstream defaulted member is split into
// extensions in this port): whole-array write, startIndex-only write, and boundary errors.

fun drain(buf: Buffer): String {
    val out = ByteArray(buf.size.toInt())
    buf.readAtMostTo(out, 0, out.size)
    return String(out)
}

fun main() {
    val buf = Buffer()

    buf.write(byteArrayOf(104, 101, 108, 108, 111)) // "hello" via write(ByteArray)
    println(drain(buf))

    buf.write(byteArrayOf(63, 33, 33), 1) // write(ByteArray, Int) -> "!!"
    println(drain(buf))

    buf.write(byteArrayOf(1, 2, 3, 4), 1, 3) // member form -> bytes 2,3
    println(drain(buf))

    buf.write(ByteArray(0)) // empty write is a no-op
    println(buf.size)

    val b2 = Buffer()
    try {
        b2.write(byteArrayOf(1), -1, 1)
    } catch (e: IndexOutOfBoundsException) {
        println("ioobe: ${e.message}")
    }
    try {
        b2.write(byteArrayOf(1), 0, 5)
    } catch (e: IndexOutOfBoundsException) {
        println("ioobe2: ${e.message}")
    }
    try {
        b2.write(byteArrayOf(1, 2), 2, 1)
    } catch (e: IllegalArgumentException) {
        println("iae: ${e.message}")
    }
    try {
        b2.write(byteArrayOf(9), -2)
    } catch (e: IndexOutOfBoundsException) {
        println("ioobe3: ${e.message}")
    }
    println(b2.size)
}
