// KUU-2267: Elvis should preserve Number as the common type of a nullable
// type parameter and the Int fallback, while an unguarded nullable-bound call
// remains invalid in the Sema regression test.
fun <T : Number?> foo(t: T) {
    (t ?: 42).toInt()
}

fun <T : Number?> convert(t: T): Int = (t ?: 42).toInt()

fun box(): String {
    foo<Int?>(null)
    if (convert<Int?>(null) != 42) return "FAIL"
    return "OK"
}

fun main() {
    println(box())
}
