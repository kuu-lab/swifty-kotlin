// KUU-3171 / KUU-3743: check an erased result at its consuming type.
private fun <T> Any?.uncheckedCast(): T = this as T
private fun <T> foo(): T = Any() as T

private class Marker {
    override fun toString(): String = "marker"
}

fun main() {
    try {
        println(Marker().uncheckedCast<Int?>())
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
