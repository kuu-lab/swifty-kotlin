// KUU-1348: deferred non-null writes preserve outer null-check narrowing.
class CaptureBuffer { fun readString(): String = "buffer" }

fun localFunctionFinally() {
    var buffer: CaptureBuffer? = null
    fun fill() { if (buffer == null) buffer = CaptureBuffer() }
    try { fill() } finally {
        if (buffer != null) println(buffer.readString())
    }
}

fun main() {
    localFunctionFinally()
    var buffer: CaptureBuffer? = null
    val fill = { buffer = CaptureBuffer() }
    fill()
    if (buffer != null) println(buffer.readString())
}
