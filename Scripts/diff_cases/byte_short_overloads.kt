fun f(x: Byte): String = "byte"
fun f(x: Short): String = "short"

fun main() {
    println(f(1.toByte()))
    println(f(1.toShort()))
}
