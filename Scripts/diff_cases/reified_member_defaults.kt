package fixture

class Factory {
    inline fun <reified T : Enum<T>> choice(noinline value: () -> Int = { 7 }): Array<T> = enumValues<T>()
    inline fun <reified T> name(value: Int = 0): String = T::class.simpleName ?: "?"
    inline fun <reified T> empty(value: Int = 0): Array<T> = emptyArray<T>()
    fun control(value: Int = 11): Int = value
}

class GenericFactory<C> {
    inline fun <reified A, reified B> names(prefix: String = ""): String =
        prefix + A::class.simpleName + ":" + B::class.simpleName
}

fun stringCount(vararg values: String): Int = values.size
fun nestedCount(vararg values: Array<String>): Int = values.size
fun rejected(action: () -> Unit): String = try { action(); "OK" } catch (_: IllegalArgumentException) { "IAE" }

enum class Entry { A, B }
enum class Other { X, Y, Z }

fun main() {
    val factory = Factory()
    println(factory.choice<Entry>().toList())
    println(factory.choice<Other>({ 9 }).toList())
    println(factory.name<String>())
    println(factory.name<Int>(1))
    val strings = ::stringCount
    println(strings.callBy(mapOf(strings.parameters[0] to factory.empty<String>())))
    println(rejected { strings.callBy(mapOf(strings.parameters[0] to factory.empty<Int>(1))) })
    val nested = ::nestedCount
    println(nested.callBy(mapOf(nested.parameters[0] to factory.empty<Array<String>>(1))))
    println(rejected { nested.callBy(mapOf(nested.parameters[0] to factory.empty<Array<Int>>())) })
    println(factory.control())
    println(factory.control(13))
    val generic = GenericFactory<Long>()
    println(generic.names<String, Int>())
    println(generic.names<Int, String>("explicit:"))
}
