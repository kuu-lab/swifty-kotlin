// KUU-1240: an unsuffixed index must adapt to get(Long), preserving its Byte result.
class Buf {
    operator fun get(position: Long): Byte = (position + 40L).toByte()
}

fun f(b: Buf) {
    val x = b[0].toInt()
    val y = b[0L].toInt()
    println(x)
    println(y)
    println(b[1].toInt())
    println(b.get(1).toInt())
}

fun acceptLong(value: Long): Long = value

fun main() {
    f(Buf())
    println(acceptLong(0))
    val l: Long = 0
    println(l)
}
