import kotlin.reflect.*

annotation class Names(val label: String, vararg val values: String)
fun collect(vararg values: String): Int = values.size
fun sum(vararg values: Int): Int = values.sum()

fun main() {
    val constructor = Names::class.constructors.single()
    val names = constructor.call("label", arrayOf("a", "b"))
    println(names.label)
    println(names.values.size)
    println(names.values[1])
    println(::collect.call(arrayOf("x", "y", "z")))
    println(::sum.call(intArrayOf(2, 3)))
}
