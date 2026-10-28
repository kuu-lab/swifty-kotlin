// KUU-3171: an unchecked `as T` must be checked when a generic result is
// claimed at a concrete nullable primitive or reference type.
private fun <T> Any?.uncheckedCast(): T = this as T
private fun <T> foo(): T = Any() as T

fun main() {
    try {
        println(Any().uncheckedCast<Int?>())
    } catch (e: ClassCastException) {
        println("OK")
    }

    try {
        println(foo<String>().length)
    } catch (e: ClassCastException) {
        println("OK")
    }

    println(42.uncheckedCast<Int?>())
}
