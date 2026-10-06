enum class E { A, B }
enum class Other { X, Y, Z }
enum class Empty

inline fun <reified T : Enum<T>> values(unused: Int = 0): List<T> = enumValues<T>().toList()
inline fun <reified T : Enum<T>> nestedValues(): List<T> = values<T>()

class Factory {
    companion object {
        inline fun <reified T : Enum<T>> choices(unused: Int = 0): List<T> = enumValues<T>().toList()
    }
}

fun main() {
    println(values<E>())
    println(values<Other>())
    println(nestedValues<E>())
    println(values<Empty>())
    println(values<kotlin.annotation.AnnotationRetention>())
    println(Factory.choices<E>())
    val first = enumValues<E>()
    first[0] = E.B
    println(values<E>())
}
