// KUU-1289: establish non-nullness for a mutable capture within a local function.
class Buf {
    fun write(count: Long) { println(count) }
}

fun main() {
    var buf: Buf? = null
    fun g(count: Long) {
        if (count > 0L) {
            if (buf == null) {
                buf = Buf()
            }
            buf.write(count)
        }
    }
    g(0L)
    g(1L)
    g(2L)
}
