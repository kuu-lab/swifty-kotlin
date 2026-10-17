import kotlinx.io.*

class FailedStartsWithSource : RawSource {
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = throw IOException("source failure")

    override fun close() {}
}

fun main() {
    val buffer = Buffer().also { it.write(byteArrayOf(1, 2, 3)) }
    val source: Source = buffer

    println(source.startsWith(1))
    println(buffer.size)
    println(source.readByte().toInt())
    println(source.startsWith(9))
    println(buffer.size)
    println(source.readByte().toInt())
    println(source.startsWith(3))
    println(buffer.size)
    println(source.readByte().toInt())
    println(source.startsWith(3))
    println(buffer.size)

    val closedSource: Source = (Buffer() as RawSource).buffered()
    closedSource.close()
    try {
        closedSource.startsWith(1)
        println("missing closed-source exception")
    } catch (_: IllegalStateException) {
        println("IllegalStateException")
    }

    val failedSource = FailedStartsWithSource().buffered()
    try {
        failedSource.startsWith(1)
        println("missing source exception")
    } catch (_: IOException) {
        println("IOException")
    }
}
