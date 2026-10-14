// KUU-2105: preserve the fallback for nullable generic returns with a default
// argument, including both reference and primitive specializations.
fun <T : Any?> someFunc(a: T, arg: T? = null): T = arg ?: a

fun box(): String {
    var key: String? = null
    key = someFunc("a")
    if (key != "a") return "FAIL1"
    key = someFunc("a", "b")
    if (key != "b") return "FAIL2"

    var key1: Int? = null
    key1 = someFunc(42)
    if (key1 != 42) return "FAIL3"
    key1 = someFunc(42, 24)
    if (key1 != 24) return "FAIL3"
    return "OK"
}

fun main() {
    println(box())
}
