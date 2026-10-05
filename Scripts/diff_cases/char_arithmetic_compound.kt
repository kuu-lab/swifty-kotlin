var top: Char = 'a'
class Holder { var c: Char = 'a' }

operator fun Char.plus(other: Char): Char = (this.code + other.code).toChar()
operator fun Char.times(other: Int): Char = (this.code * other).toChar()
operator fun Char.divAssign(other: Int) { println(this.code / other) }
operator fun Char.minusAssign(other: String) { println(other) }

fun main() {
    var c: Char = 'a'
    val holder = Holder()
    val chars = arrayOf('a')
    c += 2
    top += 2
    holder.c += 2
    chars[0] += 2
    println(c)
    println(top)
    println(holder.c)
    println(chars[0])
    c -= 2
    top -= 2
    holder.c -= 2
    chars[0] -= 2
    println(c)
    println(top)
    println(holder.c)
    println(chars[0])
    c += '\u0001'
    top += '\u0001'
    holder.c += '\u0001'
    chars[0] += '\u0001'
    c *= 2
    top *= 2
    holder.c *= 2
    chars[0] *= 2
    println(c.code)
    println(top.code)
    println(holder.c.code)
    println(chars[0].code)
    c /= 2
    top /= 2
    holder.c /= 2
    chars[0] /= 2
}
