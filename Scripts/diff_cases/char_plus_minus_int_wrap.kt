fun shift(c: Char, d: Int): Char = c + d

fun main() {
    println(shift('￿', 1).code)
    println(shift('a', -98).code)
    println(shift('￿', 1) == '\u0000')
    println(('a' - 98).code)
}
