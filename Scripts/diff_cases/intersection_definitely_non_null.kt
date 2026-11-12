// DIFF_JVM
fun <T> nonNull(value: T & Any): T & Any = value
fun <T> identity(value: T): T = value
fun Any.idTag(): Int = 7

fun <T : Any?> directValue(x: T & Any): Int = x.idTag()
fun <T : Any?> safeValue(x: T & Any): Int? = x?.idTag()

fun main() {
    println(nonNull<String>("ok"))
    println(identity<String?>(null) ?: "ordinary-null")
    println(directValue("hello"))
    println(safeValue("world"))
}
