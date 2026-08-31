fun noElseGuard(x: Int): Int {
    val result = 0
    when {
        x > 10 -> result
        x > 0 -> result
    }
    return result
}

fun main() {
    println(noElseGuard(5))
    println(noElseGuard(-5))
}
