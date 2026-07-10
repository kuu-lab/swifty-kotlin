fun main() {
    val n: Long = -1L
    println(n.toUInt())
    println(n.toUInt() == 4294967295u)
    println((-1).toUInt())
    println((-1).toLong().toUInt())
    println((n and 0xffffffffL).toInt().toUInt())
    println((n and 0xffffffffL).toUInt())
    println(4294967295u.toInt())
    println(2147483648u.toInt())
    println(4294967296uL.toInt())
    println(4294967295uL.toInt())
}
