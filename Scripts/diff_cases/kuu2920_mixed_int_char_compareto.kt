operator fun Int.compareTo(c: Char) = 0

fun foo(x: Int, y: Char): String {
    if (x < y) throw Error()
    return "OK"
}

fun main() { println(foo(42, 'O')) }
