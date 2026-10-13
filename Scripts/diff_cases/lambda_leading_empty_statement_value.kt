fun main() {
    println(run { ; 7 })
    val y = { ; 42 }()
    println(y)
    println(if (true) { ; 7 } else { 8 })
}
