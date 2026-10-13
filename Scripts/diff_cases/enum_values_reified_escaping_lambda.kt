// KUU-2033: escaping lambdas retain the class token in a captured reified Pair.
package fixture

inline fun <reified T : Enum<T>> valuesFactory(): () -> Array<T> = { enumValues<T>() }
inline fun <reified T : Enum<T>> nestedValuesFactory(): () -> () -> Array<T> = { { enumValues<T>() } }
// Generic Enum.name lowering is tracked separately by KUU-2037.
inline fun <reified T : Enum<T>> countFactory(prefix: String): () -> String = {
    prefix + enumValues<T>().size
}
inline fun <reified T : Enum<T>> mappedValuesFactory(prefix: String): () -> List<String> = {
    listOf(1).map { prefix + enumValues<T>().size }
}

enum class E { A, B }
enum class F { X, Y, Z }
enum class Empty

fun main() {
    val e = valuesFactory<E>()
    val f = valuesFactory<F>()
    println(e().toList())
    println(f().toList())
    val first = e()
    first[0] = E.B
    println(e()[0].name)
    println(valuesFactory<Empty>()().size)
    println(nestedValuesFactory<E>()()().toList())
    println(countFactory<F>("count:")())
    println(mappedValuesFactory<E>("mapped:")())
    println(enumValues<E>().toList())
}
