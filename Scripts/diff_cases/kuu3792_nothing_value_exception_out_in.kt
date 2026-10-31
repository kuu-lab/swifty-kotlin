// KUU-3792: `Any() as T` with T inferred to Nothing through an `out`-projected
// argument feeding an `in`-projected parameter throws KotlinNothingValueException.
// Mirrors JetBrains codegen/box nothingValueException.kt.
fun <T> something(): T = Any() as T
class Context<T>
fun <T> Any.decodeIn(typeFrom: Context<in T>): T = something()
fun <T> Any?.decodeOut(typeFrom: Context<out T>): T {
    return this?.decodeIn(typeFrom)
        ?: throw AssertionError("")
}
fun box(): String {
    try {
        "str".decodeOut(Context<Any>())
    } catch (e: Exception) {
        return if (e::class.simpleName == "KotlinNothingValueException") "OK"
               else throw AssertionError("Unexpected exception: $e")
    }
    throw AssertionError("Should fail with exception")
}
fun main() { println(box()) }
