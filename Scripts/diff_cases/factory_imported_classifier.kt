package factorycollision

import kotlinx.io.*

fun Sink(): Buffer = Buffer()

fun Sink(value: Int): Buffer {
    val buffer = Buffer()
    buffer.writeInt(value)
    return buffer
}

fun Sink.preview(): Int {
    val buffer: Buffer = this as Buffer
    return buffer.size.toInt()
}

fun use(value: Sink): Int {
    val typed: Sink = value
    return typed.preview()
}

fun main() {
    val empty: Sink = Sink()
    val filled = Sink(42)
    println(use(empty))
    println(use(filled))
    println(filled.readInt())
}
