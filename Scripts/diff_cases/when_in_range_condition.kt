fun hex(b: Int): Int = when (b) {
    in '0'.code..'9'.code -> b - '0'.code
    in 'a'.code..'f'.code -> b - 'a'.code + 10
    in 'A'.code..'F'.code -> b - 'A'.code + 10
    else -> -1
}

fun main() {
    println(hex('7'.code))
    println(hex('b'.code))
    println(hex('Z'.code))
}
