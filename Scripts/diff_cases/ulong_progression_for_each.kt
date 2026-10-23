fun main() {
    var s = 0
    (5UL downTo 1UL).forEach { s = s * 10 + it.toInt() }
    println(s)
}
