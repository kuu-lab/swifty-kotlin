package golden.sema

fun main() {
    val empty = ubyteArrayOf()
    val values = ubyteArrayOf(1.toUByte(), 255.toUByte(), 3.toUByte())
    println(empty.size)
    println(values.size)
    println(values[0])
    println(values[1])
    println(values[2])
}
