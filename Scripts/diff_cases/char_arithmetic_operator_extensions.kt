operator fun Char.plus(other: Char): Int = this.code + other.code
operator fun Char.plus(other: Int): Int = this.code + other
operator fun Char.times(other: Int): Int = this.code * other
operator fun Char.div(other: Int): Int = this.code / other
operator fun Char.rem(other: Int): Int = this.code % other
operator fun Int.plus(other: Char): Int = this + other.code

fun main() {
    val c: Char = 'a'
    val other: Char = 'b'
    val offset: Int = 2
    val shifted: Char = c + offset
    val previous: Char = c - offset
    val distance: Int = c - other
    println(shifted)
    println(previous)
    println(distance)
    println(c + other)
    println(c * offset)
    println(c / offset)
    println(c % offset)
    println(offset + c)
    println(c + "bc")
    println("bc" + c)
    println(c.plus(offset))
    println(c.minus(offset))
    println(c.minus(other))
    println(2 + 3)
    println(6 * 7)
    println(7.5 / 2.5)
}
