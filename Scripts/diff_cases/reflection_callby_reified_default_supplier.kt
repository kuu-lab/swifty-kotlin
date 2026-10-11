import kotlin.reflect.KFunction

inline fun <reified T> defaultArray(supplier: () -> Array<T> = { emptyArray<T>() }): Array<T> = supplier()
fun defaultStringWords(vararg values: String): Int = values.size
fun defaultNestedWords(vararg values: Array<String>): Int = values.size

fun main() {
    val strings = ::defaultStringWords
    val nested = ::defaultNestedWords
    val emptyStrings = defaultArray<String>()
    val emptyNested = defaultArray<Array<String>>()
    println("default-captured-string:" + strings.callBy(mapOf(strings.parameters[0] to emptyStrings)))
    println("default-captured-nested:" + nested.callBy(mapOf(nested.parameters[0] to emptyNested)))
}
