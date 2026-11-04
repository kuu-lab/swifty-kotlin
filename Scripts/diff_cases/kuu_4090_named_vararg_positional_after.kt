// KUU-4090: Kotlin 1.4+ mixed named/positional arguments — once a vararg
// parameter is filled by name, positional arguments continue binding the
// remaining parameters in declaration order.
fun f(vararg keys: String, listener: Int) {
    println("keys=${keys.size} listener=$listener")
}

fun k(vararg v: String, a: Int, b: Int) {
    println("v=${v.size} a=$a b=$b")
}

fun m(a: Int, vararg keys: String, listener: Int) {
    println("a=$a keys=${keys.size} listener=$listener")
}

fun main() {
    f(keys = arrayOf("a", "b"), 5)
    f(keys = *arrayOf("x"), 7)
    k(v = arrayOf("y"), 1, 2)
    m(9, keys = arrayOf("k"), 8)
}
