class Decoder(val value: Int)
class Buffer

fun withBuffer(block: Buffer.() -> Int): Int = Buffer().block()
fun Buffer.nested(block: String.() -> Int): Int = "inner".block()
fun Decoder.decodeImpl(max: Int): Int = value + max
fun Decoder.decode(max: Int): Int = withBuffer {
    nested { decodeImpl(max) }
}

fun main() {
    println(Decoder(7).decode(3))
    println(Decoder(20).decode(4))
}
