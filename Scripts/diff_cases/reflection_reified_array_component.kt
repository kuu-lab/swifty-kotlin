inline fun <reified T> componentEmpty(): Array<T> = emptyArray<T>()
inline fun <reified T> componentViaLambda(): Array<T> {
    val supplier = { emptyArray<T>() }
    return supplier()
}
inline fun <reified T> componentClass(value: T): String = T::class.simpleName ?: "?"
inline fun <reified T> componentDefault(label: String = "d"): String = label + ":" + T::class.simpleName
fun componentStrings(vararg values: String): Int = values.size
fun componentNested(vararg values: Array<String>): Int = values.size
fun componentRejected(action: () -> Unit): String = try { action(); "OK" } catch (_: IllegalArgumentException) { "IAE" }

fun main() {
    println("nonvararg-class:" + componentClass<String>("x"))
    println("nonvararg-default:" + componentDefault<String>())
    val strings = ::componentStrings
    println("reified-empty:" + strings.callBy(mapOf(strings.parameters[0] to componentEmpty<String>())))
    println("reified-captured-empty:" + strings.callBy(mapOf(strings.parameters[0] to componentViaLambda<String>())))
    val nested = ::componentNested
    println("reified-nested-empty:" + nested.callBy(mapOf(nested.parameters[0] to componentEmpty<Array<String>>())))
    println("reified-wrong-component:" + componentRejected { nested.callBy(mapOf(nested.parameters[0] to componentEmpty<Array<Int>>())) })
}
