@Suppress("UNCHECKED_CAST")
private fun <T : Comparable<T>> read(value: Any?): T? = value as T?

private fun <T : Comparable<T>> forward(value: T?): T? = read<T>(value)

fun main() {
    println(forward<Int>(null))
    println(forward(7))
    try {
        val number: Int? = read<Int>("wrong")
        println(number?.plus(1))
    } catch (exception: ClassCastException) {
        println("wrong type")
    }
    println(emptyArray<Int>().minOrNull())
    println(emptyArray<Int>().maxOrNull())
    println(arrayOf(3, 1).minOrNull())
    println(arrayOf(3, 1).maxOrNull())
}
