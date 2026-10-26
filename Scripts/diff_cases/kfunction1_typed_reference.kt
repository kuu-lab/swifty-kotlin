import kotlin.reflect.KFunction1

fun length(value: String): Int = value.length

fun main() {
    val function: KFunction1<String, Int> = ::length
    println(function("Kotlin!"))
}
