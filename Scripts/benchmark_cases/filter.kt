fun main() {
    val result = (1..100000).filter { it > 50000 }.sum()
    println(result)
}
