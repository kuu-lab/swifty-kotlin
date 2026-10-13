import structures.*
fun main() {
    val a = matrix { row(1, 2); row(3, 4) }
    val b = matrix { row(5, 6); row(7, 8) }
    println(a + b)
    println(a * b)
}
