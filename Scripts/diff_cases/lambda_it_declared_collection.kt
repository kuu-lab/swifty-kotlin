fun main() {
    val ops2: List<(Int) -> Int> = listOf({ it + 1 }, { it * 2 })
    println(ops2.map { it(10) })
    val ops3 = listOf<(Int, Int) -> Int>({ a, b -> a + b })
    println(ops3[0](1, 2))
}
