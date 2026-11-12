// DIFF_JVM
enum class Color { RED, BLUE }
enum class Larger { FIRST, SECOND, THIRD }
enum class Empty

inline fun <reified T : Enum<T>> enumCount() = enumValues<T>().size
inline fun <reified T : Enum<T>> enumArray(): Array<T> = enumValues()

fun colorCount() = enumCount<Color>()
fun colorValues() = enumArray<Color>()
fun largerCount() = enumCount<Larger>()
fun largerValues() = enumArray<Larger>()
fun emptyCount() = enumCount<Empty>()
fun emptyValues() = enumArray<Empty>()

fun main() {
    println(colorCount())
    println(colorValues()[0].name)
    println(colorValues()[1].name)
    println(largerCount())
    println(largerValues()[0].name)
    println(largerValues()[1].name)
    println(largerValues()[2].name)
    println(emptyCount())
    println(emptyValues().size)
}
