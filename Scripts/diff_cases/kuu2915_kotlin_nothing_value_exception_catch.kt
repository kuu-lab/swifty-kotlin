// KUU-2915: A normally returning generic Nothing call must throw a catchable exception.
fun <T> something(): T = Any() as T

fun <T> Any.decodeIn(typeFrom: Any?): T = something()

fun <T> Any?.decodeOut(typeFrom: Any?): T =
    this?.decodeIn(typeFrom) ?: throw AssertionError()

fun main() {
    try {
        "s".decodeOut<Nothing>(null)
    } catch (e: Exception) {
        println(e::class.simpleName)
    }
}
