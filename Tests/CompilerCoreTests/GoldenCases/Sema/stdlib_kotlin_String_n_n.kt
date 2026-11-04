package golden.sema

fun takeString(value: String): String = value

fun codePointsToString(codePoints: IntArray): String = String(codePoints, 0, 1)

fun main() {
    val empty: String = String()
    val typed = takeString(empty)
    println(typed == "")
    println(typed.length)
    println(typed + "x")
    println(codePointsToString(intArrayOf(0x1F600)))
}
