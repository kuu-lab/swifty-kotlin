import kotlin.ExperimentalContextParameters

fun contextOf(): String = "user contextOf"

fun context(a: Int): Int = a * 2

@OptIn(ExperimentalContextParameters::class)
fun main() {
    println(contextOf())
    println(context(5))
    println(context(7) { contextOf<Int>() * 2 })
}
