import kotlin.reflect.KFunction

inline fun <reified T> defaultArray(supplier: () -> Array<T> = { emptyArray<T>() }): Array<T> = supplier()
fun defaultStringWords(vararg values: String): Int = values.size
fun defaultNestedWords(vararg values: Array<String>): Int = values.size
