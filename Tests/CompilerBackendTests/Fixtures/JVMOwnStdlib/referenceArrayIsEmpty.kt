fun empty(values: Array<out Any?>): Boolean = values.isEmpty()
fun main() {
    println(emptyArray<String>().isEmpty())
    println(arrayOf<String?>(null).isEmpty())
    println(empty(arrayOf("x")))
    println(empty(emptyArray<Any?>()))
    println(listOf(1).isEmpty())
}
