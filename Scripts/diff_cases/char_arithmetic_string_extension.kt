operator fun Char.plus(other: String): Int = this.code + other.length

fun main() {
    println('a' + "bc")
    println('a'.plus("bc"))
}
