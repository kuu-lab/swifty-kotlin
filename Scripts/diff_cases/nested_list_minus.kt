fun <T> sub(a: List<List<T>>, b: List<List<T>>) = a - b

fun main() {
    for (x in sub(listOf(listOf(1), listOf(2)), listOf(listOf(2)))) println(x)
    println(listOf(1, 2, 3) - 2)
    println(listOf(1, 2, 3) - listOf(1))
}
