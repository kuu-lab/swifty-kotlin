private fun <T> collect(block: MutableList<T>.() -> Unit): List<T> = buildList(block)

fun main() {
    var escaped: MutableList<Int>? = null
    val result = collect<Int> { add(1); add(2); escaped = this }
    println(result)
    println(result is MutableList<*>)
    println(result is ArrayList<*>)
    println(result is java.util.RandomAccess)
    try {
        escaped!!.add(3)
        println("mutated")
    } catch (e: UnsupportedOperationException) {
        println("frozen")
    }
    println(result)
}
