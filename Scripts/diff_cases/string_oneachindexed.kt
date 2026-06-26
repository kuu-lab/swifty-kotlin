fun main() {
    val result = "abc".onEachIndexed { index, c -> print("$index:$c ") }
    println()
    println(result)
}
